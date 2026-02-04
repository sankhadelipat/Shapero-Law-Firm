public without sharing class QuickBooksInvoiceService
    implements Queueable, Database.AllowsCallouts {

    /* ===============================
       STATE
       =============================== */
    private List<Id> invoiceIds;
    private Boolean forceUpdate;

    /* ===============================
       CONSTRUCTOR
       =============================== */
    public QuickBooksInvoiceService(
        List<Id> invoiceIds,
        Boolean forceUpdate
    ) {
        this.invoiceIds = invoiceIds;
        this.forceUpdate = forceUpdate;
    }

    /* ===============================
       BUTTON / LWC ENTRY
       =============================== */
@AuraEnabled
public static void createInvoice(Id invoiceId) {

    if (invoiceId == null) {
        throw new AuraHandledException('Invoice Id is required');
    }

    Invoice__c inv = [
        SELECT Id, Invoice_Date__c, Due_Date__c
        FROM Invoice__c
        WHERE Id = :invoiceId
        LIMIT 1
    ];

    // ❌ Validation BEFORE async call
    if (inv.Invoice_Date__c == null || inv.Due_Date__c == null) {
        throw new AuraHandledException(
            'Invoice Date and Due Date are required before creating a QuickBooks invoice'
        );
    }

    // ✅ Only enqueue if validation passes
    System.enqueueJob(
        new QuickBooksInvoiceService(
            new List<Id>{ invoiceId },
            false
        )
    );
}


    /* ===============================
       TRIGGER ENTRY
       =============================== */
    public static void createInvoiceAuto(
        Set<Id> invoiceIds,
        Boolean forceUpdate
    ) {
        if (invoiceIds == null || invoiceIds.isEmpty()) return;

        System.enqueueJob(
            new QuickBooksInvoiceService(
                new List<Id>(invoiceIds),
                forceUpdate
            )
        );
    }

    /* ===============================
       QUEUEABLE EXECUTION
       =============================== */
    public void execute(QueueableContext ctx) {

        system.debug('invoiceIds in QuickBookInvoiceService:' + invoiceIds);

        if (invoiceIds.isEmpty()) return;

        String realmId = QuickBooks_Config__mdt.getInstance('Default').Realm_Id__c;

        /* ===============================
           FETCH INVOICES
           =============================== */
        Map<Id, Invoice__c> invoiceMap =
            new Map<Id, Invoice__c>([
                SELECT Id,
                       Name,
                       Status__c,
                       Invoice_Date__c,
                       Due_Date__c,
                       QBO_Invoice_ID__c,
                       QBO_Invoice_Number__c,
                       Account__r.QBO_Customer_ID__c
                FROM Invoice__c
                WHERE Id IN :invoiceIds
            ]);

        system.debug('invoiceMap in QuickBookInvoiceService:' + JSON.serializePretty(invoiceMap));
        if (invoiceMap.isEmpty()) return;

        /* ===============================
           FETCH LINE ITEMS
           =============================== */
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
            WHERE Invoice__c IN :invoiceMap.keySet()
        ]) {
            if (!lineMap.containsKey(li.Invoice__c)) {
                lineMap.put(
                    li.Invoice__c,
                    new List<Invoice_Line_Item__c>()
                );
            }
            lineMap.get(li.Invoice__c).add(li);
        }
        system.debug('lineMap in QuickBookInvoiceService:' + lineMap);

        /* ===============================
           FETCH EXPENSES (NO AGGREGATE)
           =============================== 
        Set<Id> invoicesWithExpense = new Set<Id>();

        for (Expense__c exp : [
            SELECT Invoice__c
            FROM Expense__c
            WHERE Invoice__c IN :invoiceMap.keySet()
            AND Amount__c > 0
        ]) {
            invoicesWithExpense.add(exp.Invoice__c);
        }
*/
        Http http = new Http();
        List<Invoice__c> updates = new List<Invoice__c>();

        /* ===============================
           PROCESS INVOICES
           =============================== */
        for (Invoice__c inv : invoiceMap.values()) {

            // ---- Guards ----
            if (!forceUpdate) {
                system.debug('forceUpdate: ' + forceUpdate);
                System.debug('inv.Status__c: ' + inv.Status__c + ' -- inv.QBO_Invoice_ID__c: ' + inv.QBO_Invoice_ID__c);
                if (//inv.Status__c != 'Draft' ||
                    !String.isBlank(inv.QBO_Invoice_ID__c)) {
                    continue;
                }
            }

        //    if (!invoicesWithExpense.contains(inv.Id)) continue;
            if (!lineMap.containsKey(inv.Id)) continue;
            if (String.isBlank(inv.Account__r.QBO_Customer_ID__c)) continue;

            Boolean isNew = String.isBlank(inv.QBO_Invoice_ID__c);

            try {
                HttpRequest req =
                    buildInvoiceRequest(
                        inv,
                        lineMap.get(inv.Id),
                        realmId
                    );

                if (!isNew) {
                    String syncToken =
                        fetchSyncToken(
                            inv.QBO_Invoice_ID__c,
                            realmId
                        );
                    if (syncToken == null) continue;

                    Map<String, Object> body =
                        (Map<String, Object>)
                            JSON.deserializeUntyped(
                                req.getBody()
                            );
                    body.put('Id', inv.QBO_Invoice_ID__c);
                    body.put('SyncToken', syncToken);
                    req.setBody(JSON.serialize(body));
                }

                HttpResponse res = http.send(req);

                if (res.getStatusCode() == 200 ||
                    res.getStatusCode() == 201) {

                    Map<String, Object> resp =
                        (Map<String, Object>)
                            JSON.deserializeUntyped(
                                res.getBody()
                            );
                    Map<String, Object> qboInv =
                        (Map<String, Object>)
                            resp.get('Invoice');

                    updates.add(new Invoice__c(
                        Id = inv.Id,
                        QBO_Invoice_ID__c =
                            (String) qboInv.get('Id'),
                        QBO_Invoice_Number__c =
                            (String) qboInv.get('DocNumber')
                    ));
                }

            } catch (Exception e) {
                System.debug(
                    'QBO ERROR → ' + inv.Id +
                    ' → ' + e.getMessage()
                );
            }
        }

        if (!updates.isEmpty()) {
            update updates;
        }
    }

    /* ===============================
       BUILD REQUEST
       =============================== */
    private static HttpRequest buildInvoiceRequest(
        Invoice__c inv,
        List<Invoice_Line_Item__c> lines,
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

        List<Object> qboLines = new List<Object>();
        for (Invoice_Line_Item__c li : lines) {
            qboLines.add(buildLine(li));
        }

        body.put('Line', qboLines);
        req.setBody(JSON.serialize(body));
        return req;
    }

    private static Map<String, Object> buildLine(
        Invoice_Line_Item__c li
    ) {
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

        if (li.Tax_Percentage__c != null &&
            li.Tax_Percentage__c > 0) {
            ((Map<String, Object>)
                line.get('SalesItemLineDetail'))
                .put(
                    'TaxCodeRef',
                    new Map<String, Object>{
                        'value' => 'TAX'
                    }
                );
        }

        return line;
    }

    /* ===============================
       FETCH SYNC TOKEN
       =============================== */
    private static String fetchSyncToken(
        String qboInvoiceId,
        String realmId
    ) {
        if (String.isBlank(qboInvoiceId)) return null;

        try {
            HttpRequest req = new HttpRequest();
            req.setMethod('GET');
            req.setEndpoint(
                'callout:QBO_Named_Credential/v3/company/' +
                realmId + '/invoice/' + qboInvoiceId
            );
            req.setHeader('Accept', 'application/json');

            HttpResponse res = new Http().send(req);
            if (res.getStatusCode() == 200) {
                Map<String, Object> resp =
                    (Map<String, Object>)
                        JSON.deserializeUntyped(
                            res.getBody()
                        );
                return (String)
                    ((Map<String, Object>)
                        resp.get('Invoice'))
                        .get('SyncToken');
            }
        } catch (Exception e) {
            System.debug(
                'SYNC TOKEN ERROR → ' + e.getMessage()
            );
        }
        return null;
    }
}