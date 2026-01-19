public class StripePaymentMethodQueueable implements Queueable, Database.AllowsCallouts {
    private static final StripeAuth__c STRIPE_AUTH = StripeAuth__c.getOrgDefaults();
    private static final String STRIPE_API_URL = STRIPE_AUTH.API_URL__c;
    private static final String SECRET_KEY = STRIPE_AUTH.SECRET_KEY__c;

    private String paymentMethodId;

    public StripePaymentMethodQueueable(String paymentMethodId) {
        this.paymentMethodId = paymentMethodId;
    }

    public void execute(QueueableContext context) {
        try {
            HttpRequest req = new HttpRequest();
            req.setEndpoint(STRIPE_API_URL + '/payment_methods/' + paymentMethodId);
            req.setMethod('GET');
            req.setHeader('Authorization', 'Basic ' + EncodingUtil.base64Encode(Blob.valueOf(SECRET_KEY + ':')));

            Http http = new Http();
            HttpResponse res = http.send(req);

            if (res.getStatusCode() == 200) {
                Map<String, Object> paymentMethod = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                System.debug('Fetched Payment Method: ' + paymentMethod);

                // Create or update the Payment Method record
                Payment_Method__c pm = buildPaymentMethodRecord(paymentMethod);
                upsert pm Stripe_Payment_Method_Id__c;
            } else {
                System.debug('Failed to fetch Payment Method. Status Code: ' + res.getStatusCode());
            }
        } catch (Exception e) {
            System.debug('Error in StripePaymentMethodQueueable: ' + e.getMessage());
        }
    }

    private Payment_Method__c buildPaymentMethodRecord(Map<String, Object> paymentMethod) {
        String paymentMethodId = (String) paymentMethod.get('id');
        String paymentMethodType = (String) paymentMethod.get('type');
        Map<String, Object> billingDetails = (Map<String, Object>) paymentMethod.get('billing_details');

        Map<String, Object> addressObj = billingDetails != null ? (Map<String, Object>) billingDetails.get('address') : null;

        Map<String, String> address = new Map<String, String>();
        if (addressObj != null) {
            for (String key : addressObj.keySet()) {
                if (addressObj.get(key) != null) {
                    address.put(key, String.valueOf(addressObj.get(key)));
                }
            }
        }

        String billingName = billingDetails != null ? (String) billingDetails.get('name') : null;
        String billingEmail = billingDetails != null ? (String) billingDetails.get('email') : null;
        String billingPhone = billingDetails != null ? (String) billingDetails.get('phone') : null;
        String customerId = (String) paymentMethod.get('customer');
        Id accountId;
        Id leadId;

        // Fetch associated Account or Lead based on Customer ID
        List<Account> accounts = [
            SELECT Id
            FROM Account
            WHERE Stripe_Customer_ID__c = :customerId
            LIMIT 1
        ];

        List<Lead> leads = [
            SELECT Id
            FROM Lead
            WHERE Stripe_Customer_ID__c = :customerId
            LIMIT 1
        ];

        if (!accounts.isEmpty()) {
            accountId = accounts[0].Id;
        } else if (!leads.isEmpty()) {
            leadId = leads[0].Id;
        } else {
            throw new DmlException('No associated Account or Lead found for Customer ID: ' + customerId);
        }
        System.debug('Associated Account Id: ' + accountId + ', Lead Id: ' + leadId);

        Payment_Method__c pm = new Payment_Method__c(
            Stripe_Payment_Method_Id__c = paymentMethodId,
            Billing_Name__c = billingName,
            Billing_Email__c = billingEmail,
            Billing_Phone__c = billingPhone,
            Account__c = accountId,
            Lead__c = leadId
        );

        // Card details
        if (paymentMethodType == 'card' && paymentMethod.containsKey('card')) {
            Map<String, Object> cardDetails = (Map<String, Object>) paymentMethod.get('card');
            pm.Name = (String) cardDetails.get('brand') + ' ' + cardDetails.get('last4');
            pm.RecordTypeId = Schema.SObjectType.Payment_Method__c.getRecordTypeInfosByName().get('Credit Card').getRecordTypeId();
            pm.Card_Brand__c = (String) cardDetails.get('brand');
            pm.Card_Country__c = (String) cardDetails.get('country');
            pm.Card_Expiry_Month__c = String.valueOf(cardDetails.get('exp_month'));
            pm.Card_Expiry_Year__c = String.valueOf(cardDetails.get('exp_year'));
            pm.Card_Last_4__c = (String) cardDetails.get('last4');
        }
        // Bank account details
        else if (paymentMethodType == 'us_bank_account' && paymentMethod.containsKey('us_bank_account')) {
            Map<String, Object> bankDetails = (Map<String, Object>) paymentMethod.get('us_bank_account');
            pm.Name = (String) bankDetails.get('bank_name') + ' ' + bankDetails.get('last4');
            pm.RecordTypeId = Schema.SObjectType.Payment_Method__c.getRecordTypeInfosByName().get('ACH').getRecordTypeId();
            pm.Bank_Name__c = (String) bankDetails.get('bank_name');
            pm.Bank_Account_Type__c = (String) bankDetails.get('account_type');
            pm.Bank_Account_Holder_Type__c = (String) bankDetails.get('account_holder_type');
            pm.Bank_Last_4__c = (String) bankDetails.get('last4');
        }

        return pm;
    }
}