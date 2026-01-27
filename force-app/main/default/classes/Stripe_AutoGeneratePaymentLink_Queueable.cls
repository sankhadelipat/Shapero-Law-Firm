public with sharing class Stripe_AutoGeneratePaymentLink_Queueable implements Queueable, Database.AllowsCallouts{

    private static final StripeAuth__c STRIPE_AUTH = StripeAuth__c.getOrgDefaults();
    private static final String STRIPE_API_URL = STRIPE_AUTH.API_URL__c;
    private static final String SECRET_KEY = STRIPE_AUTH.SECRET_KEY__c;

    private List<Id> invoiceIds;

    public Stripe_AutoGeneratePaymentLink_Queueable(List<Id> invoiceIds){
        this.invoiceIds = invoiceIds;
    }
    
    public void execute(QueueableContext context) {
        System.debug('invoiceIds in Stripe_AutoGeneratePaymentLink_Queueable: ' + invoiceIds);
        /* -----------------------------
           1. FETCH INVOICES
        ------------------------------*/
        //Map<Id, Invoice__c> invoiceMap = New Map<Id, Invoice__c>();
        List<Invoice__c> invoiceList = [SELECT Id, Lead__c, Lead__r.Stripe_Customer_ID__c 
                                    FROM Invoice__c 
                                    WHERE Id IN :invoiceIds];
        system.debug('invoiceList: ' + invoiceList);
        Map<Id, Invoice__c> invoiceMap = new Map<Id, Invoice__c>(invoiceList);
        
        // Map<Id, Invoice__c> invoiceMap = New Map<Id, Invoice__c>(
        //                         [SELECT Id, Lead__c, Lead__r.Stripe_Customer_ID__c 
        //                             FROM Invoice__c 
        //                             WHERE Id IN :invoiceIds]
        // );
        System.debug('Fetched Invoices: ' + invoiceMap);
        // if (invoiceMap.isEmpty()) {
        //     system.addError('No invoices found.');
        // }
        

        /* -----------------------------
           2. FETCH LINE ITEMS
        ------------------------------*/

        Map<Id, List<Invoice_Line_Item__c>> lineItemsByInvoice = new Map<Id, List<Invoice_Line_Item__c>>();
        
        for (Invoice_Line_Item__c item : [
            SELECT Id, Name, Description__c, Quantity__c, Unit_Price__c,
                   Line_Amount__c, Invoice__c
            FROM Invoice_Line_Item__c
            WHERE Invoice__c IN :invoiceIds
            ORDER BY CreatedDate ASC
        ]) {
            
            if (!lineItemsByInvoice.containsKey(item.Invoice__c)) {
                lineItemsByInvoice.put(
                    item.Invoice__c,
                    new List<Invoice_Line_Item__c>()
                );
            }
            lineItemsByInvoice.get(item.Invoice__c).add(item);
        }

        List<Invoice__c> invoicesToUpdate = new List<Invoice__c>();

        /* -----------------------------
           3. PROCESS EACH INVOICE
        ------------------------------*/
        for (Id invoiceId : invoiceIds) {
            Invoice__c invoice = invoiceMap.get(invoiceId);

            if (invoice == null) continue;

            if (String.isBlank(invoice.Lead__r.Stripe_Customer_ID__c)) {
                System.debug('No Stripe Customer ID found for Lead: ' + invoice.Lead__c);
                // throw new AuraHandledException(
                //     'Stripe Customer ID missing for Invoice: ' + invoiceId
                // );

                continue;
            }

            List<Invoice_Line_Item__c> items = lineItemsByInvoice.get(invoiceId);

            if (items == null || items.isEmpty()) {
                // throw new AuraHandledException(
                //     'Invoice has no line items: ' + invoiceId
                // );
                continue;
            }

            String checkoutUrl = createCheckoutSession(invoice, items);

            invoice.Stripe_Payment_Link__c = checkoutUrl;
            //invoice.Status__c = 'Sent';

            invoicesToUpdate.add(invoice);
        }

        /* -----------------------------
           4. UPDATE INVOICES
        ------------------------------*/
        if (!invoicesToUpdate.isEmpty()) {
            update invoicesToUpdate;
        }
        
    }

    private static String createCheckoutSession(Invoice__c invoice, List<Invoice_Line_Item__c> lineItems) 
    {

        HttpRequest request = new HttpRequest();
        request.setEndpoint(STRIPE_API_URL + '/checkout/sessions');
        request.setMethod('POST');
        request.setHeader(
            'Authorization',
            'Basic ' + EncodingUtil.base64Encode(Blob.valueOf(SECRET_KEY + ':'))
        );
        request.setHeader('Content-Type', 'application/x-www-form-urlencoded');

        List<String> bodyParts = new List<String>();
        bodyParts.add('mode=payment');
        bodyParts.add(
            'customer=' +
            EncodingUtil.urlEncode(invoice.Lead__r.Stripe_Customer_ID__c, 'UTF-8')
        );
        bodyParts.add(
            'success_url=' +
            EncodingUtil.urlEncode('https://test_success.com', 'UTF-8')
        );
        bodyParts.add(
            'cancel_url=' +
            EncodingUtil.urlEncode('https://test_error.com', 'UTF-8')
        );
        // Metadata---
        bodyParts.add('metadata[salesforce_invoice_id]=' + 
                        EncodingUtil.urlEncode(invoice.Id, 'UTF-8')
        );
        bodyParts.add('payment_intent_data[metadata][salesforce_invoice_id]=' + 
                        EncodingUtil.urlEncode(invoice.Id, 'UTF-8')
        );

        Integer index = 0;
        for (Invoice_Line_Item__c item : lineItems) {

            if (item.Unit_Price__c == null || item.Quantity__c == null) {
                // throw new AuraHandledException(
                //     'Invalid line item data on Invoice ' + invoice.Id
                // );
                continue;
            }

            Integer unitAmount = Integer.valueOf(item.Unit_Price__c * 100);

            bodyParts.add(
                'line_items[' + index + '][price_data][product_data][name]=' +
                EncodingUtil.urlEncode(item.Name, 'UTF-8')
            );

            if (!String.isBlank(item.Description__c)) {
                bodyParts.add(
                    'line_items[' + index + '][price_data][product_data][description]=' +
                    EncodingUtil.urlEncode(item.Description__c, 'UTF-8')
                );
            }

            bodyParts.add(
                'line_items[' + index + '][price_data][unit_amount]=' + unitAmount
            );
            bodyParts.add(
                'line_items[' + index + '][price_data][currency]=usd'
            );
            bodyParts.add(
                'line_items[' + index + '][quantity]=' +
                Integer.valueOf(item.Quantity__c)
            );

            index++;
        }

        request.setBody(String.join(bodyParts, '&'));

        Http http = new Http();
        HttpResponse response = http.send(request);

        System.debug('response.getStatusCode()--> ' + response.getStatusCode());
        System.debug('response.getBody()--> ' + response.getBody());
        if (response.getStatusCode() != 200) {
            system.debug(
                'Stripe error for Invoice ' + invoice.Id + ': ' + response.getBody()
            );
            // throw new AuraHandledException(
            //     'Stripe error for Invoice ' + invoice.Id + ': ' + response.getBody()
            // );
            return null;
        }

        Map<String, Object> responseMap =
            (Map<String, Object>) JSON.deserializeUntyped(response.getBody());

        return (String) responseMap.get('url');
    }



    
}