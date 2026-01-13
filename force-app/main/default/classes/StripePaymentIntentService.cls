public class StripePaymentIntentService {
    private static final StripeAuth__c STRIPE_AUTH = StripeAuth__c.getOrgDefaults();
    private static final String STRIPE_API_URL = STRIPE_AUTH.API_URL__c;
    private static final String SECRET_KEY = STRIPE_AUTH.SECRET_KEY__c;
    private static final String PUBLISHABLE_KEY = STRIPE_AUTH.PUBLISHABLE_KEY__c;

    public class PaymentIntentResponse {
        @AuraEnabled
        public Boolean success;
        @AuraEnabled
        public String clientSecret;
        @AuraEnabled
        public String errorMessage;
    }

    @AuraEnabled
    public static PaymentIntentResponse createPaymentIntent(Decimal amount, Id invoiceId) {
        PaymentIntentResponse response = new PaymentIntentResponse();

        try {
            if (amount == null || amount <= 0) {
                throw new HandledException('Invalid amount.');
            } else if (String.isBlank(invoiceId)) {
                throw new HandledException('Invalid invoice.');
            }

            // Fetch customer ID from Lead & Account related to the Invoice
            Invoice__c invoice = [
                SELECT Id, Account__c, Account__r.Stripe_Customer_ID__c, Lead__c, Lead__r.Stripe_Customer_ID__c
                FROM Invoice__c
                WHERE Id = :invoiceId
                LIMIT 1
            ];
            System.debug('Fetched Invoice: ' + invoice);

            String customerId;

            if (invoice.Account__r != null && String.isNotBlank(invoice.Account__r.Stripe_Customer_ID__c)) {
                customerId = invoice.Account__r.Stripe_Customer_ID__c;
            } else if (invoice.Lead__r != null && String.isNotBlank(invoice.Lead__r.Stripe_Customer_ID__c)) {
                customerId = invoice.Lead__r.Stripe_Customer_ID__c;
            }

            Integer amountInCents = Integer.valueOf((amount * 100));

            HttpRequest req = new HttpRequest();
            req.setEndpoint(STRIPE_API_URL + '/payment_intents');
            req.setMethod('POST');
            req.setHeader('Authorization', 'Basic ' + EncodingUtil.base64Encode(Blob.valueOf(SECRET_KEY + ':')));
            req.setHeader('Content-Type', 'application/x-www-form-urlencoded');

            List<String> bodyParts = new List<String>();
            bodyParts.add('amount=' + amountInCents);
            bodyParts.add('currency=usd');
            bodyParts.add('automatic_payment_methods[enabled]=true');
            if (String.isNotBlank(customerId))
                bodyParts.add('customer=' + EncodingUtil.urlEncode(customerId, 'UTF-8'));
            bodyParts.add('metadata[salesforce_invoice_id]=' + EncodingUtil.urlEncode(String.valueOf(invoiceId), 'UTF-8'));

            String body = String.join(bodyParts, '&');
            req.setBody(body);

            Http http = new Http();
            HttpResponse res = http.send(req);

            if (res.getStatusCode() == 200) {
                Map<String, Object> paymentIntent = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                System.debug('Created Payment Intent: ' + paymentIntent);

                String clientSecret = (String) paymentIntent.get('client_secret');
                response.success = true;
                response.clientSecret = clientSecret;
                return response;
            } else {
                throw new CalloutException(
                    'Failed to create Payment Intent. Status Code: ' + res.getStatusCode() + ', Body: ' + res.getBody()
                );
            }
        } catch (Exception e) {
            response.success = false;
            response.errorMessage = e.getMessage();
            return response;
        }
    }

    @AuraEnabled(cacheable=true)
    public static String getStripePublishableKey() {
        return PUBLISHABLE_KEY;
    }
}