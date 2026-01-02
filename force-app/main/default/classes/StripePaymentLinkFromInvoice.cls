public with sharing class StripePaymentLinkFromInvoice {
    private static final StripeAuth__c STRIPE_AUTH = StripeAuth__c.getOrgDefaults();
    private static final String STRIPE_API_URL = STRIPE_AUTH.API_URL__c;
    private static final String SECRET_KEY = STRIPE_AUTH.SECRET_KEY__c;

    public class Result {
        @InvocableVariable
        public Boolean isSuccess;

        @InvocableVariable
        public String message;
    }

    @InvocableMethod(label='Generate Payment Link' description='Generates a Stripe Checkout Session payment link.')
    public static List<Result> generatePaymentLink(List<Id> invoiceIds) {
        List<Result> results = new List<Result>();
        Result res = new Result();
        results.add(res);

        if (invoiceIds == null || invoiceIds.isEmpty()) {
            res.isSuccess = false;
            res.message = 'No Invoice Id provided.';
            return results;
        }

        try {
            Id invoiceId = invoiceIds[0];

            // Fetch invoice
            Invoice__c invoice = [
                SELECT Id, Account__c, Account__r.Stripe_Customer_ID__c, Lead__c, Lead__r.Stripe_Customer_ID__c
                FROM Invoice__c
                WHERE Id = :invoiceId
                LIMIT 1
            ];
            System.debug('Fetched Invoice: ' + invoice);

            String customerId;

            if (String.isNotBlank(invoice.Account__r.Stripe_Customer_ID__c)) {
                customerId = invoice.Account__r.Stripe_Customer_ID__c;
            } else if (String.isNotBlank(invoice.Lead__r.Stripe_Customer_ID__c)) {
                customerId = invoice.Lead__r.Stripe_Customer_ID__c;
            } else {
                throw new HandledException('No Stripe Customer Id found on related Account or Lead.');
            }

            // Fetch invoice line items
            List<Invoice_Line_Item__c> lineItems = [
                SELECT Id, Name, Description__c, Quantity__c, Unit_Price__c, Invoice__c
                FROM Invoice_Line_Item__c
                WHERE Invoice__c = :invoiceId
                ORDER BY CreatedDate ASC
            ];
            System.debug('Fetched Line Items: ' + lineItems);

            if (lineItems.isEmpty()) {
                throw new HandledException('Invoice has no line items.');
            }

            HttpRequest request = new HttpRequest();
            request.setEndpoint(STRIPE_API_URL + '/checkout/sessions');
            request.setMethod('POST');
            request.setHeader('Authorization', 'Basic ' + EncodingUtil.base64Encode(Blob.valueOf(SECRET_KEY + ':')));
            request.setHeader('Content-Type', 'application/x-www-form-urlencoded');

            List<String> bodyParts = new List<String>();
            bodyParts.add('mode=payment');
            bodyParts.add('customer=' + EncodingUtil.urlEncode(customerId, 'UTF-8'));
            bodyParts.add('success_url=' + EncodingUtil.urlEncode('https://test_success.com', 'UTF-8'));
            bodyParts.add('cancel_url=' + EncodingUtil.urlEncode('https://test_error.com', 'UTF-8'));
            // Metadata
            bodyParts.add('metadata[salesforce_invoice_id]=' + EncodingUtil.urlEncode(invoice.Id, 'UTF-8'));
            bodyParts.add('payment_intent_data[metadata][salesforce_invoice_id]=' + EncodingUtil.urlEncode(invoice.Id, 'UTF-8'));

            Integer index = 0;
            for (Invoice_Line_Item__c item : lineItems) {
                if (item.Unit_Price__c == null || item.Quantity__c == null) {
                    throw new HandledException('Line item "' + item.Name + '" is missing amount or quantity.');
                }

                bodyParts.add('line_items[' + index + '][price_data][product_data][name]=' + EncodingUtil.urlEncode(item.Name, 'UTF-8'));
                if (String.isNotBlank(item.Description__c))
                    bodyParts.add(
                        'line_items[' +
                            index +
                            '][price_data][product_data][description]=' +
                            EncodingUtil.urlEncode(item.Description__c, 'UTF-8')
                    );
                bodyParts.add('line_items[' + index + '][price_data][unit_amount]=' + Integer.valueOf(item.Unit_Price__c * 100));
                bodyParts.add('line_items[' + index + '][price_data][currency]=usd');
                bodyParts.add('line_items[' + index + '][quantity]=' + Integer.valueOf(item.Quantity__c));

                index++;
            }

            request.setBody(String.join(bodyParts, '&'));
            Http http = new Http();
            HttpResponse response = http.send(request);
            System.debug('Stripe Response: ' + response.getBody());

            if (response.getStatusCode() == 200) {
                Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
                String checkoutUrl = (String) responseMap.get('url');
                System.debug('Checkout URL: ' + checkoutUrl);

                invoice.Stripe_Payment_Link__c = checkoutUrl;
                update invoice;

                res.isSuccess = true;
                res.message = 'Payment link generated successfully.';
                return results;
            } else {
                throw new HandledException('Error from Stripe: ' + response.getBody());
            }
        } catch (Exception e) {
            System.debug('Error generating payment link: ' + e.getMessage());
            res.isSuccess = false;
            res.message = e.getMessage();
            return results;
        }
    }
}