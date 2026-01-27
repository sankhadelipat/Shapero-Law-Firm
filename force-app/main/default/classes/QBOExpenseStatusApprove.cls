public class QBOExpenseStatusApprove {

    @future(callout=true)
    public static void updateBillableStatus(List<Id> expenseIds) {

        QuickBooks_Config__mdt config =
            QuickBooks_Config__mdt.getInstance('Default');

         String realmId = config.Realm_Id__c;
         List<Expense__c> expenses = [
                            SELECT Id,
                                   QBO_Expense_Id__c,
                                   QBO_Sync_Status__c,
                                   QBO_Sync_Error__c,
                                   Account__c,
                                   Account__r.QBO_Customer_Id__c
                            FROM Expense__c
                            WHERE Id IN :expenseIds
                            AND QBO_Expense_Id__c != null
                        ];

        for (Expense__c exp : expenses) {
            try {
                HttpRequest getReq = new HttpRequest();
                getReq.setEndpoint(
                    'callout:QBO_Named_Credential/v3/company/' +
                    realmId + '/purchase/' + exp.QBO_Expense_Id__c +
                    '?minorversion=75'
                );
                getReq.setMethod('GET');
                getReq.setHeader('Accept', 'application/json');

                HttpResponse getRes = new Http().send(getReq);
                String body = getRes.getBody();

                System.debug('QBO GET BODY => ' + body);

                Map<String, Object> purchase =
                    (Map<String, Object>)
                    ((Map<String, Object>) JSON.deserializeUntyped(body))
                    .get('Purchase');

                String syncToken   = (String) purchase.get('SyncToken');
            
                String paymentType = (String) purchase.get('PaymentType');

                if (paymentType == 'Check') {
                    throw new CalloutException(
                        'QBO Check transactions cannot be updated via API'
                    );
                }
                System.debug('PaymentType => ' + purchase.get('PaymentType'));


                Map<String, Object> purchaseAccountRef =
                    (Map<String, Object>) purchase.get('AccountRef');

                if (purchaseAccountRef == null) {
                    throw new CalloutException(
                        'Purchase AccountRef missing in QBO'
                    );
                }

                Map<String, Object> line =
                    (Map<String, Object>)
                    ((List<Object>) purchase.get('Line'))[0];

                String lineId = (String) line.get('Id');
                Decimal amount = (Decimal) line.get('Amount');

                Map<String, Object> abd =
                    (Map<String, Object>) line.get('AccountBasedExpenseLineDetail');

                Map<String, Object> expenseAccountRef =
                    (Map<String, Object>) abd.get('AccountRef');
                if (exp.Account__r == null ||
                    String.isBlank(exp.Account__r.QBO_Customer_Id__c)) {
                    throw new CalloutException(
                        'Account or QBO Customer Id missing. Billable requires CustomerRef.'
                    );
                }
                    // Build AccountBasedExpenseLineDetail
                    Map<String, Object> lineDetail = new Map<String, Object>{
                        'AccountRef' => expenseAccountRef,
                        'CustomerRef' => new Map<String, Object>{
                            'value' => exp.Account__r.QBO_Customer_Id__c
                        },
                        'BillableStatus' => 'Billable'
                    };
                    
                    // Build Line
                    Map<String, Object> updateLine = new Map<String, Object>{
                        'Id' => lineId, // IMPORTANT: update existing line
                        'DetailType' => 'AccountBasedExpenseLineDetail',
                        'Amount' => amount,
                        'AccountBasedExpenseLineDetail' => lineDetail
                    };
                    
                    // FINAL UPDATE PAYLOAD (MATCHES YOUR WORKING JSON)
                    Map<String, Object> updatePayload = new Map<String, Object>{
                        'Id' => exp.QBO_Expense_Id__c,
                        'SyncToken' => syncToken,               // 🔥 latest token from GET
                        'TxnDate' => (String) purchase.get('TxnDate'),
                        'TotalAmt' => purchase.get('TotalAmt'),
                        'PaymentType' => paymentType,
                        'AccountRef' => purchaseAccountRef,     // 🔥 header account from GET
                        'Line' => new List<Object>{ updateLine }
                    };
                    
                                        


                System.debug(
                    'QBO UPDATE PAYLOAD => ' +
                    JSON.serializePretty(updatePayload)
                );

                HttpRequest postReq = new HttpRequest();
                postReq.setEndpoint(
                    'callout:QBO_Named_Credential/v3/company/' +
                    realmId + '/purchase?minorversion=75'
                );
                postReq.setMethod('POST');
                postReq.setHeader('Content-Type', 'application/json');
                postReq.setHeader('Accept', 'application/json');
                postReq.setBody(JSON.serialize(updatePayload));

                HttpResponse postRes = new Http().send(postReq);

                System.debug('UPDATE STATUS => ' + postRes.getStatusCode());
                System.debug('QBO UPDATE BODY => ' + postRes.getBody());

                if (postRes.getStatusCode() == 200) {
                    exp.QBO_Sync_Status__c = 'Success';
                    exp.QBO_Sync_Error__c = null;
                } else {
                    throw new CalloutException(postRes.getBody());
                }

            } catch (Exception ex) {
                exp.QBO_Sync_Status__c = 'Failed';
                exp.QBO_Sync_Error__c = ex.getMessage();
            }
        }

        update expenses;
    }
}