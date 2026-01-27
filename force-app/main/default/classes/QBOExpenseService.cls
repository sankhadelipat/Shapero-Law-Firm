public class QBOExpenseService {

    public static List<Map<String, Object>> fetchExpenses(Datetime lastRun) {

        String lastRunStr = lastRun.formatGMT('yyyy-MM-dd\'T\'HH:mm:ss\'Z\'');
        String query = 'SELECT * FROM Purchase WHERE MetaData.LastUpdatedTime > \'' +
                       lastRunStr + '\'';

        HttpRequest req = new HttpRequest();
        req.setMethod('GET');
        req.setHeader('Accept', 'application/json');

        req.setEndpoint('callout:QBO_Named_Credential/v3/company/' +
                        	QuickBooks_Config__mdt.getInstance('Default').Realm_Id__c +
                        '/query?query=' + EncodingUtil.urlEncode(query, 'UTF-8'));

        HttpResponse res = new Http().send(req);

        if (res.getStatusCode() >= 400) {
            throw new CalloutException(res.getBody());
        }

        Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
        Map<String, Object> qr = (Map<String, Object>) body.get('QueryResponse');

        if (qr == null || !qr.containsKey('Purchase')) {
            return new List<Map<String, Object>>(); // No expenses
        }

        Object purchaseObj = qr.get('Purchase');

        List<Map<String, Object>> purchases = new List<Map<String, Object>>();

        // Normalize single vs multiple
        if (purchaseObj instanceof List<Object>) {
            for (Object o : (List<Object>) purchaseObj) {
                purchases.add((Map<String, Object>) o);
            }
        } else if (purchaseObj instanceof Map<String, Object>) {
            purchases.add((Map<String, Object>) purchaseObj);
        }

        return purchases;
    }
}