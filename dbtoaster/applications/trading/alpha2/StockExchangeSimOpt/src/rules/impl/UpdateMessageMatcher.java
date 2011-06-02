/*
 * To change this template, choose Tools | Templates
 * and open the template in the editor.
 */
package rules.impl;

import state.OrderBook;
import state.OrderBook.OrderBookEntry;
import java.io.IOException;
import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.List;
import java.util.logging.FileHandler;
import java.util.logging.Level;
import java.util.logging.Logger;
import org.jboss.netty.channel.Channel;
import rules.Matcher;
import rules.Rule;
import state.StockState;

/**
 *
 * @author kunal
 */
public class UpdateMessageMatcher implements Matcher {

    OrderBook orderBook;
    List<Rule> bidMatchRules; //The rules to match a new bid
    List<Rule> askMatchRules; //The rules to match a new ask
    StockState stockState;
    public final static Logger logger = Logger.getLogger("match_results");

    public class TimestampComparator implements Comparator {

        @Override
        public int compare(Object o1, Object o2) {
            long ts1 = ((OrderBookEntry) o1).timestamp;
            long ts2 = ((OrderBookEntry) o2).timestamp;

            if (ts1 < ts2) {
                return -1;
            } else if (ts1 > ts2) {
                return 1;
            } else {
                return 0;
            }
        }
    }

    public UpdateMessageMatcher(OrderBook dbconn, StockState stockState) throws IOException {

        orderBook = dbconn;
        bidMatchRules = new ArrayList<Rule>();
        askMatchRules = new ArrayList<Rule>();
        this.stockState = stockState;

        logger.setLevel(Level.ALL);
        FileHandler fh = new FileHandler("logfile.txt");
        logger.addHandler(fh);

    }

    @Override
    public List<OrderBookEntry> match(String action, OrderBookEntry a) {
        List<OrderBookEntry> targetOrderBook = (action.equals(OrderBook.BIDCOMMANDSYMBOL)) ? orderBook.getAskOrderBook() : orderBook.getBidOrderBook();
        List<OrderBookEntry> tupleOrderBook = (action.equals(OrderBook.ASKCOMMANDSYMBOL)) ? orderBook.getAskOrderBook() : orderBook.getBidOrderBook();

        String oppAction = (action.equals(OrderBook.ASKCOMMANDSYMBOL)) ? OrderBook.BIDCOMMANDSYMBOL : OrderBook.ASKCOMMANDSYMBOL;
        /*logger.info(String.format("---Matching new entry: %s Stock: %s, Qty: %s, Price: %s, TimeStamp: %s", action,
        a.stockId, a.volume, (a.price == OrderBook.MARKETORDER) ? "marketorder" : a.price, a.timestamp));*/
        //Step 1: Get the highest entries in the order book to match
        List<OrderBookEntry> getTopMatches = getTopMatch(action, targetOrderBook, a.stockId, a.price);

        //Step 2: See if a match is possible in terms of price. If a better price is not available, get the market orders and equals price matches
        boolean matched = false;
        if (!getTopMatches.isEmpty()) {
            matched = true;
        }
        if (!matched) {
            getTopMatches = getMarketOrders(targetOrderBook, a.stockId, a.price);
            if (!getTopMatches.isEmpty()) {
                matched = true;
            }
        }
        //Step 3: If there is match complete a trade
        if (!matched) {
            //logger.info("No match found---");
            return null;
        }

        Collections.sort(getTopMatches, new TimestampComparator());
        OrderBookEntry match = getTopMatches.get(0);
        //logger.info(String.format("Matched an entry: Stock: %s, Qty: %s, Price: %s, TimeStamp: %s---",
        //        match.stockId, match.volume, (match.price == OrderBook.MARKETORDER) ? "marketorder" : match.price, match.timestamp));
        boolean status = true;

        Channel actionChannel = this.stockState.getChannel(this.stockState.getFromMap(a.traderId));
        Channel matchChannel = this.stockState.getChannel(this.stockState.getFromMap(match.traderId));

        Double newPrice = updatePrice(a.stockId, a.price, match.price);
        if (match.volume == a.volume) {
            status = status && OrderBook.delete(targetOrderBook, match);
            status = status && OrderBook.delete(tupleOrderBook, a);
            //Send updates to relevant traders
            String currentTraderMessage = String.format("%s;stock_id:%s price:%s volume:%s order_id:%s timestamp:%s trader:%s\n",
                    action + "_update",
                    a.stockId,
                    newPrice,
                    a.volume,
                    a.order_id,
                    a.timestamp,
                    a.traderId);

            String matchTraderMessage = String.format("%s;stock_id:%s price:%s volume:%s order_id:%s timestamp:%s trader:%s\n",
                    oppAction + "_update",
                    match.stockId,
                    newPrice,
                    match.volume,
                    match.order_id,
                    match.timestamp,
                    match.traderId);
            System.err.println("Sending updates for match: \n" + currentTraderMessage + "\n" + matchTraderMessage);
            actionChannel.write(currentTraderMessage);
            matchChannel.write(matchTraderMessage);

        } else if (match.volume < a.volume) {
            status = status && OrderBook.delete(targetOrderBook, match);
            OrderBookEntry newEntry = orderBook.createEntry(a.stockId, a.price, a.volume - match.volume, a.order_id, a.timestamp, a.traderId);
            status = status && OrderBook.update(tupleOrderBook, a, newEntry);
            //Send updates to relevant traders
            String currentTraderMessage = String.format("%s;stock_id:%s price:%s volume:%s order_id:%s timestamp:%s trader:%s\n",
                    action + "_update",
                    a.stockId,
                    newPrice,
                    a.volume - match.volume,
                    a.order_id,
                    a.timestamp,
                    a.traderId);

            String matchTraderMessage = String.format("%s;stock_id:%s price:%s volume:%s order_id:%s timestamp:%s trader:%s\n",
                    oppAction + "_update",
                    match.stockId,
                    newPrice,
                    match.volume,
                    match.order_id,
                    match.timestamp,
                    match.traderId);
            System.err.println("Sending updates for match: \n" + currentTraderMessage + "\n" + matchTraderMessage);

            actionChannel.write(currentTraderMessage);
            matchChannel.write(matchTraderMessage);

            //New incoming entry is incompletely matched. Recurse.
            match(action, newEntry);
        } else {
            OrderBookEntry newEntry = orderBook.createEntry(match.stockId, match.price, match.volume - a.volume, match.order_id, match.timestamp, match.traderId);
            status = status && OrderBook.update(targetOrderBook, match, newEntry);
            status = status && OrderBook.delete(tupleOrderBook, a);
            //Send updates to relevant traders
            String currentTraderMessage = String.format("%s;stock_id:%s price:%s volume:%s order_id:%s timestamp:%s trader:%s\n",
                    action + "_update",
                    a.stockId,
                    newPrice,
                    a.volume,
                    a.order_id,
                    a.timestamp,
                    a.traderId);

            String matchTraderMessage = String.format("%s;stock_id:%s price:%s volume:%s order_id:%s timestamp:%s trader:%s\n",
                    oppAction + "_update",
                    match.stockId,
                    newPrice,
                    match.volume - a.volume,
                    match.order_id,
                    match.timestamp,
                    match.traderId);

            System.err.println("Sending updates for match: \n" + currentTraderMessage + "\n" + matchTraderMessage);

            actionChannel.write(currentTraderMessage);
            matchChannel.write(matchTraderMessage);
        }

        if (!status) {
            logger.warning("Deletion or updation from order book failed during matching");
        }

        return null;
    }

    private List<OrderBookEntry> getTopMatch(String action, List<OrderBookEntry> targetOrderBook, int stockId, double price) {
        List<OrderBookEntry> matchTargets = new ArrayList<OrderBookEntry>();
        double limit;
        boolean betterMatchExists = false;
        if (action.equals(OrderBook.BIDCOMMANDSYMBOL)) {
            limit = Integer.MAX_VALUE;
            for (OrderBookEntry e : targetOrderBook) {
                if (e.price < limit && e.stockId == stockId) {
                    limit = e.price;
                }
            }
            if (limit < price || price == OrderBook.MARKETORDER) {
                betterMatchExists = true;
            }
        } else {
            limit = Integer.MIN_VALUE;
            for (OrderBookEntry e : targetOrderBook) {
                if (e.price > limit && e.stockId == stockId) {
                    limit = e.price;
                }
            }
            if (limit > price || price == OrderBook.MARKETORDER) {
                betterMatchExists = true;
            }
        }
        if (betterMatchExists) {
            for (OrderBookEntry e : targetOrderBook) {
                if (e.price == limit) {
                    matchTargets.add(e);
                }
            }
        }

        return matchTargets;
    }

    private List<OrderBookEntry> getMarketOrders(List<OrderBookEntry> targetOrderBook, int stockId, double price) {
        List<OrderBookEntry> toReturn = new ArrayList<OrderBookEntry>();
        for (OrderBookEntry e : targetOrderBook) {
            if (e.stockId == stockId && (e.price == OrderBook.MARKETORDER || e.price == price)) {
                toReturn.add(e);
            }
        }
        return toReturn;
    }

    private Double updatePrice(int stockId, double newPrice, double matchPrice) {
        if (newPrice != OrderBook.MARKETORDER) {
            this.stockState.setStockPrice(stockId, newPrice);
            return newPrice;
        } else if (matchPrice != OrderBook.MARKETORDER) {
            this.stockState.setStockPrice(stockId, matchPrice);
            return matchPrice;
        }
        return this.stockState.getStockPrice(stockId);

    }
}
