package org.dbtoaster.cumulus.node;

import java.io.*;
import java.util.*;
import com.sleepycat.je.*;
import org.apache.log4j.Logger;

import org.dbtoaster.cumulus.net.SpreadException;

public class MultiKeyMapJavaImpl {
  public static final int DEFAULT_CACHE_SIZE = 64*1024*1024;
  
  protected static Environment env = null;
  protected Environment localEnv = null;
  
  protected final int                         numkeys;
  public    final Long                        wildcard;
  protected final Double                      defaultValue;
  protected final String                      basepath;
  protected final String                      dbName;
  protected HashMap<DatabaseEntry,MKPattern>  patterns;
  protected Database                          basemap;
  
  protected static final Logger               logger 
      = Logger.getLogger("dbtoaster.Node.MultiKeyMapJavaImpl");
    
  private static ArrayList<Long[]> translateArray(Long[][] array){
    ArrayList<Long[]> ret = new ArrayList<Long[]>();
    for(Long[] entry : array) { ret.add(entry); }
    return ret;
  }
  
  public MultiKeyMapJavaImpl(int numkeys, Long[][] patterns){
    this(numkeys, translateArray(patterns));
  }
  
  public MultiKeyMapJavaImpl(int numkeys, Long[][] patterns, String dbName, Double defaultValue){
    this(numkeys, translateArray(patterns), dbName, defaultValue);
  }
  
  public MultiKeyMapJavaImpl(int numkeys, List<Long[]> patterns){
    this(numkeys, patterns, "", 0.0);
  }

  public MultiKeyMapJavaImpl(int numkeys, List<Long[]> patterns, String dbName, Double defaultValue){
    this(numkeys, patterns, dbName, "/tmp", null, defaultValue, null);
  }

  public MultiKeyMapJavaImpl(int numkeys, List<Long[]> patterns, String dbName, String basepath, Double defaultValue){
    this(numkeys, patterns, dbName, basepath, null, defaultValue, null);
  }

  public MultiKeyMapJavaImpl(int numkeys, List<Long[]> patterns, String dbName, String basepath, String envpath, Double defaultValue){
    this(numkeys, patterns, dbName, basepath, envpath, defaultValue, null);
  }

  public MultiKeyMapJavaImpl(int numkeys, List<Long[]> patterns, String dbName, String basepath, String envpath, Double defaultValue, Long wildcard){
    this.numkeys = numkeys;
    this.wildcard = wildcard;
    this.defaultValue = defaultValue;
    this.basepath = basepath;
    this.dbName = dbName;
    this.patterns = new HashMap<DatabaseEntry,MKPattern>();
    
    System.out.println("Creating BDBJ env...");

    if ( envpath != null ) {
        EnvironmentConfig envConfig = new EnvironmentConfig();
        envConfig.setAllowCreate(true);
        envConfig.setLocking(false);
        envConfig.setTransactional(false);
        envConfig.setCacheSize(DEFAULT_CACHE_SIZE);
        localEnv = new Environment(new File(basepath, envpath), envConfig);
    }
    else if(env == null){
      EnvironmentConfig envConfig = new EnvironmentConfig();
      envConfig.setAllowCreate(true);
      envConfig.setLocking(false);
      envConfig.setTransactional(false);
      envConfig.setCacheSize(DEFAULT_CACHE_SIZE);
      env = new Environment(new File(basepath), envConfig);
    }

    System.out.println("Creating BDBJ primary...");

    String primaryName = basepath + "/db_" + dbName + "_primary.db";
    logger.debug("Creating db at : " + primaryName);
    DatabaseConfig dbConf = new DatabaseConfig();
    dbConf.setAllowCreate(true);
    //dbConf.setTemporary(false);
    //dbConf.setTransactional(true);
    dbConf.setDeferredWrite(true);
    this.basemap = getEnvironment().openDatabase(null, primaryName, dbConf);
    
    System.out.println("Opened BDBJ primary " + primaryName + " , env home " + getEnvironment().getHome() + " ...");
    if ( basemap == null ) System.out.println("Null basemap");
    else basemap.sync();
    
    for(Long[] pattern : patterns){
      add_pattern(pattern);
    }
  }
  
  Environment getEnvironment() { return localEnv == null? env : localEnv; }
  
  public String patternName(Long[] pattern){
    StringBuilder sb = new StringBuilder("{");
    String sep = "";
    for(Long element : pattern){
      sb.append(sep + element.toString());
      sep = ",";
    }
    return sb.toString()+"}";
  }
  
  public void add_pattern(Long[] pattern){
    if((pattern.length >= numkeys) || (pattern.length == 0)) { return; } // don't need to add 0 length, or full length patterns
    if(patterns.get(serializeKey(pattern)) != null) { return; }          // don't add duplicate patterns
    
    String secondaryName = basepath + "/db_" + dbName + "_" + patterns.size() + ".db";
    logger.debug("Creating secondary db (" + patternName(pattern) + ") at : " + secondaryName);
    patterns.put(serializeKey(pattern), new MKPattern(pattern, getEnvironment(), secondaryName, basemap));
  }
  
  public Double get(Long[] key){
    DatabaseEntry entry = new DatabaseEntry();
    if(basemap.get(null, serializeKey(key), entry, LockMode.DEFAULT) == OperationStatus.SUCCESS){
      logger.trace("get "+dbName+"[" + patternName(key) + "] = " + deserializeValue(entry));
      return deserializeValue(entry);
    } else {
      logger.trace("get "+dbName+"[" + patternName(key) + "] = NOT FOUND");
      return defaultValue;
    }
  }
  
  public void put(Long[] key, Double value){
    logger.trace("put "+dbName+"[" + patternName(key) + "] = " + value);
    basemap.put(null, serializeKey(key), serializeValue(value));
  }
  
  public boolean has_key(Long[] key){
    DatabaseEntry entry = new DatabaseEntry();
    entry.setPartial(0, 0, true);
    return basemap.get(null, serializeKey(key), entry, LockMode.DEFAULT) == OperationStatus.SUCCESS;
  }
  
  public void close() {
      try {
          basemap.close();
      } catch(DatabaseException dbe) {
          System.err.println("Error closing mkmap.");
          System.exit(-1);
      }
  }

  public MKFullCursor fullScan(){
    return new MKFullCursor(basemap.openCursor(null, CursorConfig.DEFAULT));
  }
  
  public MKCursor scan(Long[] partialKey) throws SpreadException {
    int cnt = 0;
    for(Long dim : partialKey){
      if(dim != wildcard) { cnt ++; }
    }
    if(cnt == numkeys){
      return null;
    }
    Long[] pattern = new Long[cnt];
    cnt = 0;
    for(int i = 0; i < partialKey.length; i++){
      if(partialKey[i] != wildcard) { pattern[cnt] = (long)i; cnt++; }
    }
    MKPattern targetPattern = patterns.get(serializeKey(pattern));
    if(targetPattern == null){
      throw new SpreadException("Request for pattern: [" + prettyPattern(pattern) + "], which doesn't exist.  Known patterns:  " + prettyListPatterns());
    }
    return targetPattern.getCursor(partialKey, basemap);
  }
  
  protected void cleanup(){
    
  }
  
  protected String prettyListPatterns(){
    StringBuffer buf = new StringBuffer();
    String sep = "";
    for(MKPattern pattern : patterns.values()){
      buf.append(pattern.toString());
      sep = "; ";
    }
    return buf.toString();
  }
  
  protected static String prettyPattern(Long[] pattern){
    StringBuffer buf = new StringBuffer("[");
    String sep = "";
    for(Long dim : pattern){
      buf.append(sep);
      buf.append(dim);
      sep = ",";
    }
    return buf.toString() + "]";
  }
  
  protected static void serializeKey(Long[] key, DatabaseEntry entry){
    StringBuilder sb = new StringBuilder();
    String sep = "";
    for(Long dim : key) { 
      sb.append(sep);
      sb.append(dim);
      sep = ",";
    }
    entry.setData(sb.toString().getBytes());
  }
  
  protected static DatabaseEntry serializeKey(Long[] key){
    DatabaseEntry entry = new DatabaseEntry();
    serializeKey(key, entry);
    return entry;
  }
  
  protected static Long[] deserializeKey(DatabaseEntry key){
    String preSplitKey = new String(key.getData());
    String[] splitKey = preSplitKey.split(",");
    Long[] parsed = new Long[splitKey.length];
    for(int i = 0; i < parsed.length; i++){
      parsed[i] = Long.parseLong(splitKey[i]);
    }
    return parsed;
  }
  
  protected static Double deserializeValue(DatabaseEntry entry){
    return new Double(new String(entry.getData()));
  }
  
  protected static DatabaseEntry serializeValue(Double entry){
    return new DatabaseEntry(entry.toString().getBytes());
  }
  
  protected class MKPattern implements SecondaryKeyCreator {
    protected final Long[] pattern;
    protected final SecondaryDatabase index;
    private Long[] patternBuffer;
    
    public MKPattern(Long[] pattern, Environment env, String databaseName, Database primaryDatabase){
      this.pattern = pattern;
      patternBuffer = new Long[pattern.length];
      
      SecondaryConfig dbConfig = new SecondaryConfig();
      dbConfig.setAllowCreate(true);
      dbConfig.setSortedDuplicates(true);
      dbConfig.setKeyCreator(this);
      index = env.openSecondaryDatabase(null, databaseName, primaryDatabase, dbConfig);
    }
    
    public MKCursor getCursor(Long[] partialKey, Database primary){
      DatabaseEntry entry = new DatabaseEntry();
      entry.setPartial(0, 0, true);
      SecondaryCursor c = index.openCursor(null, CursorConfig.DEFAULT);
      if(c.getSearchKey(createSecondaryKey(partialKey), entry, LockMode.DEFAULT) != OperationStatus.SUCCESS){
        //no matching keys
        return null;
      }
      return new MKCursor(c, primary);
    }
    
    public DatabaseEntry createSecondaryKey(Long[] key){
      DatabaseEntry result = new DatabaseEntry();
      createSecondaryKey(key, result);
      return result;
    }
    
    public void createSecondaryKey(Long[] pkey, DatabaseEntry skey){
      for(int i = 0; i < pattern.length; i++){
        patternBuffer[i] = pkey[pattern[i].intValue()];
      }
      MultiKeyMapJavaImpl.serializeKey(patternBuffer, skey);
    }
    
    public boolean createSecondaryKey(SecondaryDatabase secondary, DatabaseEntry key, DatabaseEntry data, DatabaseEntry result){
      Long[] original = MultiKeyMapJavaImpl.deserializeKey(key);
      createSecondaryKey(original, result);
      return true;
    }
    
    public String toString(){
      StringBuilder sb = new StringBuilder("<");
      String sep = "";
      for(Long dim : pattern){
        sb.append(sep + dim);
        sep = ",";
      }
      return sb.toString() + "/>";
    }
  }
  
  protected class MKFullCursor {
    protected Cursor c;
    protected DatabaseEntry key, data;
    protected boolean first;
    
    public MKFullCursor(Cursor c){
      this.c = c;
      this.first = true;
      key = new DatabaseEntry();
      data = new DatabaseEntry();
    }
    
    public boolean next(){
      if (first) {
        first = false;
        return c.getFirst(key, data, LockMode.DEFAULT) == OperationStatus.SUCCESS;
      } else {
        return c.getNext(key, data, LockMode.DEFAULT) == OperationStatus.SUCCESS;
      }
    }
    
    public Long[] key(){
      return MultiKeyMapJavaImpl.deserializeKey(key);
    }
    
    public Double value(){
      return MultiKeyMapJavaImpl.deserializeValue(data);
    }
    
    public void close(){
      c.close();
    }
  }
  
  protected class MKCursor {
    protected SecondaryCursor c;
    protected Database primary;
    protected DatabaseEntry key, pKey, data;
    protected boolean first;
    
    public MKCursor(SecondaryCursor c, Database primary){
      this.c = c;
      this.primary = primary;
      key = new DatabaseEntry();
        key.setPartial(0, 0, true);
      pKey = new DatabaseEntry();
      data = new DatabaseEntry();
      first = true;
    }
    
    public void replace(Double value){
      primary.put(null, pKey, MultiKeyMapJavaImpl.serializeValue(value));
    }
    
    public boolean next(){
      if (first) { 
        first = false;
        return c.getCurrent(key, pKey, data, LockMode.DEFAULT) == OperationStatus.SUCCESS;
      } else {
        return c.getNextDup(key, pKey, data, LockMode.DEFAULT) == OperationStatus.SUCCESS;
      }
    }
    
    public Long[] key(){
      return MultiKeyMapJavaImpl.deserializeKey(pKey);
    }
    
    public Double value(){
      return MultiKeyMapJavaImpl.deserializeValue(data);
    }
    
    public void close(){
      c.close();
    }
  }
}