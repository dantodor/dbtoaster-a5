package org.dbtoaster.io;

import java.util.HashSet;
import java.util.LinkedHashMap;
import java.util.LinkedList;
import java.util.Map;
import java.util.Vector;

import org.apache.commons.lang.StringEscapeUtils;
import org.dbtoaster.model.DatasetManager;
import org.dbtoaster.model.DatasetManager.Dataset;
import org.dbtoaster.io.DBToasterTMLWriter.lastRelationArgs;

public class DBToasterSourceConfigWriter
{
    DatasetManager datasetMgr;
    
    public DBToasterSourceConfigWriter(DatasetManager dMgr)
    {
        datasetMgr = dMgr;
    }
    
    private LinkedList<String> indent(LinkedList<String> sl)
    {
        LinkedList<String> r = new LinkedList<String>();
        for (String s: sl) r.add("    " + s);
        return r;
    }
    
    public String createConfiguration(String sourceConfigs)
    {
        return "<sources>\n" + sourceConfigs + "</sources>";
    }

    // TODO: check XML quoting of values used during string construction
    public String getSourceConfiguration(
            Vector<lastRelationArgs> lastRelationsUsed)
    {
        HashSet<String> uniqueRelations = new HashSet<String>();
        LinkedList<String> configLines = new LinkedList<String>();

        for (lastRelationArgs e : lastRelationsUsed)
        {
            String datasetName = e.getDataset();
            String relName = e.getRelName();
            String uniqueName = datasetName + "." + relName; 

            System.out.println("Creating source config for " + uniqueName);

            if ( uniqueRelations.contains(uniqueName) ) continue;

            Dataset ds = datasetMgr.getDataset(datasetName);
            
            // TODO: more graceful error handling, e.g. throw an exception.
            if ( !ds.hasRelation(relName) ) return null;
                
            String streamType = ds.getStreamType(relName);

            String sourceType = ds.getSourceType(relName);
            String sourceInstance = ds.getSourceInstance(relName);

            LinkedList<String> argLines = new LinkedList<String>();
            LinkedList<String> defaultArgs = ds.getDefaultConstructorArgs(relName);
            for (int i = 0; i < defaultArgs.size(); ++i) {
                String arg = "<arg pos=\"" + Integer.toString(i) +
                    "\" val=\"" + StringEscapeUtils.escapeXml(defaultArgs.get(i)) + "\"/>";
                argLines.add(arg);
            }

            LinkedList<String> bindingLines = new LinkedList<String>();
            for (Map.Entry<String, String> b : ds.getBindings(relName).entrySet())
            {
                String binding = "<binding queryname=\"" + b.getKey() +
                    "\" tuplename=\"" + b.getValue() + "\"/>"; 
                bindingLines.add(binding);
            }
            
            configLines.add("<relation name=\"" + relName + "\">");
            configLines.add("<stream type=\"" + streamType + "\"/>");
            configLines.add("<source type=\"" + sourceType +
                "\" instance =\"" + sourceInstance + "\">");
            configLines.addAll(indent(argLines));
            configLines.add("</source>");
            
            configLines.add("<tuple type=\"" + ds.getTupleType(relName) + "\"/>");
            
            configLines.add("<adaptor type=\"" + ds.getAdaptorType(relName) + "\">");
            configLines.addAll(indent(bindingLines));
            configLines.add("</adaptor>");
            
            configLines.add("<thrift namespace=\"" + ds.getThriftNamespace(relName) + "\"/>");
            configLines.add("</relation>");

            uniqueRelations.add(uniqueName);
        }
        
        System.out.println("Done with source configs");


        String scBody = "";
        for (String s : indent(configLines)) scBody += (s+"\n");

        return scBody;
    }
}