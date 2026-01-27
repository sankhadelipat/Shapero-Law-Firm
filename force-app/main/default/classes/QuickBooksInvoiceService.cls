public with sharing class QuickBooksInvoiceService {

    /* ==================================
       Called from LWC / Flow
       ================================== */
    @AuraEnabled
    public static void createInvoice(Id invoiceId) {

        Invoice__c inv = [
            SELECT Id,
                   QBO_Invoice_ID__c,
                   Account__r.QBO_Customer_ID__c
            FROM Invoice__c
            WHERE Id = :invoiceId
            LIMIT 1
        ];

        if (!String.isBlank(inv.QBO_Invoice_ID__c)) {
            throw new AuraHandledException('Invoice already synced to QuickBooks');
        }

        if (String.isBlank(inv.Account__r.QBO_Customer_ID__c)) {
            throw new AuraHandledException('Customer is not synced to QuickBooks');
        }

        createInvoicesAsync(new List<Id>{ invoiceId });
    }

    /* ==================================
       Async Callout
       ================================== */
    @future(callout=true)
    private static void createInvoicesAsync(List<Id> invoiceIds) {

        String realmId =
            QuickBooks_Config__mdt.getInstance('Default').Realm_Id__c;

        List<Invoice__c> invoices = [
            SELECT Id, Name,
                   Invoice_Date__c,
                   Due_Date__c,
                   QBO_Invoice_ID__c,
                   Account__r.QBO_Customer_ID__c
            FROM Invoice__c
            WHERE Id IN :invoiceIds
        ];

      Map<Id, List<Invoice_Line_Item__c>> lineMap =
    new Map<Id, List<Invoice_Line_Item__c>>();

for (Invoice_Line_Item__c li : [
    SELECT Id,
           Invoice__c,
           Description__c,
           Quantity__c,
           Unit_Price__c,
           Line_Amount__c,
           Tax_Percentage__c,
           QBO_Item_Id__c
    FROM Invoice_Line_Item__c
    WHERE Invoice__c IN :invoiceIds
]) {
    if (!lineMap.containsKey(li.Invoice__c)) {
        lineMap.put(li.Invoice__c, new List<Invoice_Line_Item__c>());
    }
    lineMap.get(li.Invoice__c).add(li);
}

        Http http = new Http();
        List<Invoice__c> updates = new List<Invoice__c>();

        for (Invoice__c inv : invoices) {

            if (!String.isBlank(inv.QBO_Invoice_ID__c) ||
                String.isBlank(inv.Account__r.QBO_Customer_ID__c)) {
                continue;
            }

            List<Invoice_Line_Item__c> lines = lineMap.get(inv.Id);
            if (lines == null || lines.isEmpty()) {
                System.debug('No line items found for invoice ' + inv.Id);
                continue;
            }

            try {
                HttpRequest req = buildRequest(inv, lines, realmId);
                HttpResponse res = http.send(req);

                if (res.getStatusCode() == 200 || res.getStatusCode() == 201) {

                    Map<String, Object> resp =
                        (Map<String, Object>) JSON.deserializeUntyped(res.getBody());

                    Map<String, Object> qboInv =
                        (Map<String, Object>) resp.get('Invoice');

                    updates.add(new Invoice__c(
                        Id = inv.Id,
                        QBO_Invoice_ID__c = (String) qboInv.get('Id'),
                        QBO_Invoice_Number__c = (String) qboInv.get('DocNumber')
                    ));
                } else {
                    System.debug('QBO ERROR: ' + res.getBody());
                }

            } catch (Exception e) {
                System.debug('QBO EXCEPTION: ' + e.getMessage());
            }
        }

        if (!updates.isEmpty()) {
            update updates;
        }
    }

    /* ==================================
       Build HTTP Request
       ================================== */
    private static HttpRequest buildRequest(
        Invoice__c inv,
        List<Invoice_Line_Item__c> lineItems,
        String realmId
    ) {

        HttpRequest req = new HttpRequest();
        req.setMethod('POST');
        req.setEndpoint(
            'callout:QBO_Named_Credential/v3/company/' +
            realmId + '/invoice'
        );
        req.setHeader('Content-Type', 'application/json');
        req.setHeader('Accept', 'application/json');

        Map<String, Object> body = new Map<String, Object>{
            'TxnDate' => inv.Invoice_Date__c.format(),
            'DueDate' => inv.Due_Date__c.format(),
            'DocNumber' => inv.Name,
            'CustomerRef' => new Map<String, Object>{
                'value' => inv.Account__r.QBO_Customer_ID__c
            }
        };

        List<Map<String, Object>> qboLines = new List<Map<String, Object>>();

        for (Invoice_Line_Item__c li : lineItems) {
            qboLines.add(buildLine(li));
        }

        body.put('Line', qboLines);
        req.setBody(JSON.serialize(body));
        System.debug(JSON.serialize(body));

        return req;
    }

    /* ==================================
       Build Line Item from Salesforce
       ================================== */
    private static Map<String, Object> buildLine(Invoice_Line_Item__c li) {

        Map<String, Object> line = new Map<String, Object>{
            'DetailType' => 'SalesItemLineDetail',
            'Amount' => li.Line_Amount__c,
            'Description' => li.Description__c,
            'SalesItemLineDetail' => new Map<String, Object>{
                'Qty' => li.Quantity__c,
                'UnitPrice' => li.Unit_Price__c,
                'ItemRef' => new Map<String, Object>{
                    'value' => li.QBO_Item_Id__c
                }
            }
        };

        // Optional Tax
        if (li.Tax_Percentage__c != null && li.Tax_Percentage__c > 0) {
            ((Map<String, Object>) line.get('SalesItemLineDetail'))
                .put('TaxCodeRef', new Map<String, Object>{
                    'value' => 'TAX' // or map dynamically
                });
        }

        return line;
    }
}