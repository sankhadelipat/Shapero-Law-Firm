public with sharing class StripeAutoChargeInvoice {
    private static final StripeAuth__c STRIPE_AUTH = StripeAuth__c.getOrgDefaults();
    private static final String STRIPE_API_URL = STRIPE_AUTH.API_URL__c;
    private static final String SECRET_KEY = STRIPE_AUTH.SECRET_KEY__c;

    public class Request {
        @InvocableVariable
        public Decimal amount;
        @InvocableVariable
        public Id invoiceId;
        @InvocableVariable
        public String paymentMethodId;
    }

    public class Result {
        @InvocableVariable
        public Boolean isSuccess;
        @InvocableVariable
        public String status;
        @InvocableVariable
        public String message;
        @InvocableVariable
        public String paymentIntentId;
    }

    @InvocableMethod(
        label='Auto Charge Invoice'
        description='Automatically charge the customer for the given Invoice using saved payment methods.'
    )
    public static List<Result> autoChargeInvoice(List<Request> requests) {
        List<Result> results = new List<Result>();
        Result res = new Result();
        results.add(res);

        if (requests == null || requests.isEmpty()) {
            res.isSuccess = false;
            res.message = 'No Invoice Id provided.';
            return results;
        }

        try {
            Request req = requests[0];
            Id invoiceId = req.invoiceId;
            Decimal amount = req.amount;
            String paymentMethodId = req.paymentMethodId;

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

            // Create a Payment Intent to charge the customer
            HttpRequest request = new HttpRequest();
            request.setEndpoint(STRIPE_API_URL + '/payment_intents');
            request.setMethod('POST');
            request.setHeader('Authorization', 'Basic ' + EncodingUtil.base64Encode(Blob.valueOf(SECRET_KEY + ':')));
            request.setHeader('Content-Type', 'application/x-www-form-urlencoded');

            List<String> bodyParts = new List<String>();
            bodyParts.add('amount=' + Integer.valueOf(amount * 100));
            bodyParts.add('currency=usd');
            bodyParts.add('confirm=true');
            bodyParts.add('automatic_payment_methods[enabled]=true');
            bodyParts.add('automatic_payment_methods[allow_redirects]=never');
            bodyParts.add('payment_method=' + EncodingUtil.urlEncode(paymentMethodId, 'UTF-8'));
            if (String.isNotBlank(customerId))
                bodyParts.add('customer=' + EncodingUtil.urlEncode(customerId, 'UTF-8'));
            bodyParts.add('metadata[salesforce_invoice_id]=' + EncodingUtil.urlEncode(String.valueOf(invoiceId), 'UTF-8'));

            request.setBody(String.join(bodyParts, '&'));
            Http http = new Http();
            HttpResponse response = http.send(request);
            System.debug('Intent Response: ' + response.getBody());

            if (response.getStatusCode() == 200) {
                Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(response.getBody());
                String paymentIntentId = (String) responseMap.get('id');
                String status = (String) responseMap.get('status');
                System.debug('Intent Status: ' + status);

                if (status == 'succeeded') {
                    res.isSuccess = true;
                    res.status = status;
                    res.message = 'Invoice charged successfully.';
                    res.paymentIntentId = paymentIntentId;
                } else if (status == 'processing') {
                    res.isSuccess = true;
                    res.status = status;
                    res.message = 'Invoice charge is processing. May take 1-2 business days.';
                    res.paymentIntentId = paymentIntentId;
                } else {
                    res.isSuccess = false;
                    res.status = status;
                    res.message = 'Invoice charge failed with status: ' + status;
                    res.paymentIntentId = paymentIntentId;
                }
            } else {
                throw new HandledException('Error from Stripe: ' + response.getBody());
            }
        } catch (Exception e) {
            System.debug('Error in autoChargeInvoice: ' + e.getMessage());
            res.isSuccess = false;
            res.message = e.getMessage();
        }

        return results;
    }
}
