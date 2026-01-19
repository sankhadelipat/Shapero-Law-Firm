@RestResource(urlMapping='/stripe/webhook')
global without sharing class StripeWebhook {
    @HttpPost
    global static void handleWebhook() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;

        String requestBody = req.requestBody.toString();
        System.debug('Received Stripe Webhook: ' + requestBody);

        Map<String, Object> payload = (Map<String, Object>) JSON.deserializeUntyped(requestBody);
        String eventType = (String) payload.get('type');
        System.debug('Event Type: ' + eventType);

        // if (eventType.equals('checkout.session.completed')) {
        //     Map<String, Object> data = (Map<String, Object>) payload.get('data');
        //     Map<String, Object> session = (Map<String, Object>) data.get('object');
        //     String checkoutSessionId = (String) session.get('id');
        //     String paymentIntentId = (String) session.get('payment_intent');
        //     Map<String, Object> metadata = (Map<String, Object>) session.get('metadata');
        //     String salesforceInvoiceId = metadata != null && metadata.containsKey('salesforce_invoice_id')
        //         ? (String) metadata.get('salesforce_invoice_id')
        //         : null;

        //     System.debug('Checkout Session ID: ' + checkoutSessionId);
        //     System.debug('Payment Intent ID: ' + paymentIntentId);
        //     System.debug('Salesforce Invoice ID: ' + salesforceInvoiceId);

        //     System.enqueueJob(new StripePaymentIntentQueueable(paymentIntentId, salesforceInvoiceId, eventType));
        // }

        if (eventType.equals('payment_method.attached')) {
            Map<String, Object> data = (Map<String, Object>) payload.get('data');
            Map<String, Object> paymentMethod = (Map<String, Object>) data.get('object');
            String paymentMethodId = (String) paymentMethod.get('id');
            System.debug('Payment Method ID: ' + paymentMethodId);

            System.enqueueJob(new StripePaymentMethodQueueable(paymentMethodId));
        } else if (eventType.equals('payment_intent.succeeded') || eventType.equals('payment_intent.payment_failed')) {
            Map<String, Object> data = (Map<String, Object>) payload.get('data');
            Map<String, Object> paymentIntent = (Map<String, Object>) data.get('object');
            String paymentIntentId = (String) paymentIntent.get('id');
            Map<String, Object> metadata = (Map<String, Object>) paymentIntent.get('metadata');
            String salesforceInvoiceId = metadata != null && metadata.containsKey('salesforce_invoice_id')
                ? (String) metadata.get('salesforce_invoice_id')
                : null;

            System.debug('Payment Intent ID: ' + paymentIntentId);
            System.debug('Salesforce Invoice ID: ' + salesforceInvoiceId);

            System.enqueueJob(new StripePaymentIntentQueueable(paymentIntentId, salesforceInvoiceId, eventType));
        }
    }
}