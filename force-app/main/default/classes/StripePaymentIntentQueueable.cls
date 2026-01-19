public class StripePaymentIntentQueueable implements Queueable, Database.AllowsCallouts {
    private static final StripeAuth__c STRIPE_AUTH = StripeAuth__c.getOrgDefaults();
    private static final String STRIPE_API_URL = STRIPE_AUTH.API_URL__c;
    private static final String SECRET_KEY = STRIPE_AUTH.SECRET_KEY__c;

    private String paymentIntentId;
    private Id salesforceInvoiceId;
    private String eventType;

    public StripePaymentIntentQueueable(String paymentIntentId, Id salesforceInvoiceId, String eventType) {
        this.paymentIntentId = paymentIntentId;
        this.salesforceInvoiceId = salesforceInvoiceId;
        this.eventType = eventType;
    }

    public void execute(QueueableContext context) {
        try {
            HttpRequest req = new HttpRequest();
            req.setEndpoint(STRIPE_API_URL + '/payment_intents/' + paymentIntentId);
            req.setMethod('GET');
            req.setHeader('Authorization', 'Basic ' + EncodingUtil.base64Encode(Blob.valueOf(SECRET_KEY + ':')));

            Http http = new Http();
            HttpResponse res = http.send(req);

            if (res.getStatusCode() == 200) {
                Map<String, Object> paymentIntent = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                System.debug('Fetched Payment Intent: ' + paymentIntent);

                List<Invoice__c> invoices = [
                    SELECT Id, Account__c, Status__c
                    FROM Invoice__c
                    WHERE Id = :salesforceInvoiceId
                    LIMIT 1
                ];

                if (invoices.isEmpty()) {
                    System.debug('No Invoice found with Id: ' + salesforceInvoiceId);
                    return;
                }

                Invoice__c invoice = invoices[0];
                /*if (eventType == 'payment_intent.succeeded') {
                    invoice.Status__c = 'Paid';
                } else if (eventType == 'payment_intent.payment_failed') {
                    invoice.Status__c = 'Payment_Failed';
                } 

                update invoice;
                System.debug('Updated Invoice status to ' + invoice.Status__c + ' for Invoice Id: ' + invoice.Id);*/

                // Process payment intent details
                String status = eventType == 'payment_intent.succeeded'
                    ? 'Succeed'
                    : eventType == 'payment_intent.payment_failed' ? 'Failed' : 'Processing';
                Decimal amount = paymentIntent.get('amount') != null ? (Decimal) paymentIntent.get('amount') / 100 : 0;
                String stripeCurrency = paymentIntent.get('currency') != null
                    ? ((String) paymentIntent.get('currency')).toUpperCase()
                    : 'USD';
                System.debug('Amount Received: ' + amount + ' ' + stripeCurrency);

                Payment_Intent__c paymentRecord = new Payment_Intent__c();
                paymentRecord.Invoice__c = invoice.Id;
                paymentRecord.Status__c = status;
                paymentRecord.Account__c = invoice.Account__c;
                paymentRecord.Payment_Intent_ID__c = paymentIntentId;
                paymentRecord.Amount__c = amount;
                paymentRecord.Currency__c = stripeCurrency;
                paymentRecord.Description__c = (String) paymentIntent.get('description');

                upsert paymentRecord Payment_Intent_ID__c;
                System.debug('Created Payment Intent record for Invoice Id: ' + invoice.Id);
            } else {
                System.debug('Failed to fetch Payment Intent. Status: ' + res.getStatusCode() + ', Body: ' + res.getBody());
            }
        } catch (Exception e) {
            System.debug('Error processing Payment Intent: ' + e.getMessage());
        }
    }
}