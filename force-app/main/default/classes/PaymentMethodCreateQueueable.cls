public class PaymentMethodCreateQueueable implements Queueable, Database.AllowsCallouts {
    private static final StripeAuth__c STRIPE_AUTH = StripeAuth__c.getOrgDefaults();
    private static final String STRIPE_API_URL = STRIPE_AUTH.API_URL__c;
    private static final String SECRET_KEY = STRIPE_AUTH.SECRET_KEY__c;

    private List<Id> leadIds;

    public PaymentMethodCreateQueueable(List<Id> leadIds) {
        this.leadIds = leadIds;
    }

    public void execute(QueueableContext context) {
        List<Lead> leads = [SELECT Id, Stripe_Customer_ID__c FROM Lead WHERE Id IN :leadIds];

        Map<Id, List<Payment_Method__c>> pmByLead = new Map<Id, List<Payment_Method__c>>();

        for (Payment_Method__c pm : [
            SELECT
                Id,
                RecordType.Name,
                Lead__c,
                Stripe_Payment_Method_Id__c,
                Payment_Method__c,
                Credit_Card_Number__c,
                Card_Expiry_Date__c,
                Card_CVV__c,
                Card_Holder_Name__c,
                Account_Type__c,
                ACH_Account_Number__c,
                ACH_Routing_Number__c,
                Name_on_Acount__c
            FROM Payment_Method__c
            WHERE Lead__c IN :leadIds AND Stripe_Payment_Method_Id__c = NULL
        ]) {
            if (!pmByLead.containsKey(pm.Lead__c)) {
                pmByLead.put(pm.Lead__c, new List<Payment_Method__c>());
            }
            pmByLead.get(pm.Lead__c).add(pm);
        }

        for (Lead lead : leads) {
            if (pmByLead.containsKey(lead.Id)) {
                for (Payment_Method__c pm : pmByLead.get(lead.Id)) {
                    try {
                        createPaymentMethod(lead, pm);
                    } catch (Exception e) {
                        System.debug(
                            'Error in PaymentMethodCreateQueueable: ' + e.getMessage() + ' StackTrace: ' + e.getStackTraceString()
                        );
                    }
                }
            }
        }
    }

    private static void createPaymentMethod(Lead ld, Payment_Method__c pm) {
        try {
            HttpRequest req = new HttpRequest();
            req.setEndpoint(STRIPE_API_URL + '/payment_methods');
            req.setMethod('POST');
            req.setHeader('Authorization', 'Basic ' + EncodingUtil.base64Encode(Blob.valueOf(SECRET_KEY + ':')));
            req.setHeader('Content-Type', 'application/x-www-form-urlencoded');

            String pmMethod = pm.RecordType.Name;
            String type;

            if (pmMethod == 'Credit Card') {
                type = 'card';
            } else if (pmMethod == 'ACH') {
                type = 'us_bank_account';
            } else {
                System.debug('Unsupported payment method: ' + pmMethod);
                return;
            }

            List<String> bodyParams = new List<String>();
            bodyParams.add('type=' + EncodingUtil.urlEncode(type, 'UTF-8'));

            if (type == 'card') {
                String cardExpiry = pm.Card_Expiry_Date__c;
                String expMonth = '';
                String expYear = '';

                if (String.isNotBlank(cardExpiry) && cardExpiry.contains('/')) {
                    List<String> parts = cardExpiry.split('/');
                    if (parts.size() == 2) {
                        expMonth = parts[0].trim();
                        expYear = parts[1].trim();
                    }
                } else {
                    System.debug('Invalid card expiry date format for Payment Method Id: ' + pm.Id);
                    return;
                }

                bodyParams.add('card[number]=' + EncodingUtil.urlEncode(pm.Credit_Card_Number__c, 'UTF-8'));
                bodyParams.add('card[exp_month]=' + EncodingUtil.urlEncode(String.valueOf(expMonth), 'UTF-8'));
                bodyParams.add('card[exp_year]=' + EncodingUtil.urlEncode(String.valueOf(expYear), 'UTF-8'));
                bodyParams.add('card[cvc]=' + EncodingUtil.urlEncode(pm.Card_CVV__c, 'UTF-8'));
                if (String.isNotBlank(pm.Card_Holder_Name__c)) {
                    bodyParams.add('billing_details[name]=' + EncodingUtil.urlEncode(pm.Card_Holder_Name__c, 'UTF-8'));
                }
            } else if (type == 'us_bank_account') {
                String accountType;
                String accountHolderType;

                if (String.isNotBlank(pm.Account_Type__c)) {
                    if (pm.Account_Type__c.contains('Consumer')) {
                        accountHolderType = 'individual';
                    } else if (pm.Account_Type__c.contains('Business')) {
                        accountHolderType = 'company';
                    }

                    if (pm.Account_Type__c.contains('Checking')) {
                        accountType = 'checking';
                    } else if (pm.Account_Type__c.contains('Savings')) {
                        accountType = 'savings';
                    }
                } else {
                    System.debug('Missing account type or holder type for ACH payment method.');
                    return;
                }

                bodyParams.add('us_bank_account[account_number]=' + EncodingUtil.urlEncode(pm.ACH_Account_Number__c, 'UTF-8'));
                bodyParams.add('us_bank_account[routing_number]=' + EncodingUtil.urlEncode(pm.ACH_Routing_Number__c, 'UTF-8'));
                bodyParams.add('us_bank_account[account_type]=' + EncodingUtil.urlEncode(accountType, 'UTF-8'));
                bodyParams.add('us_bank_account[account_holder_type]=' + EncodingUtil.urlEncode(accountHolderType, 'UTF-8'));
                if (String.isNotBlank(pm.Name_on_Acount__c)) {
                    bodyParams.add('billing_details[name]=' + EncodingUtil.urlEncode(pm.Name_on_Acount__c, 'UTF-8'));
                }
            }

            req.setBody(String.join(bodyParams, '&'));

            Http http = new Http();
            HttpResponse res = http.send(req);

            if (res.getStatusCode() == 200) {
                Map<String, Object> paymentMethod = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
                String paymentMethodId = (String) paymentMethod.get('id');
                pm.Stripe_Payment_Method_Id__c = paymentMethodId;
                update pm;
                System.debug('Created Payment Method with ID: ' + paymentMethodId + ' for Lead Id: ' + ld.Id);

                if (type == 'card') {
                    attachPaymentMethod(ld.Stripe_Customer_ID__c, paymentMethodId);
                } else if (type == 'us_bank_account') {
                    setupACHMandate(ld.Stripe_Customer_ID__c, paymentMethodId);
                }
            } else {
                System.debug('Failed to create Payment Method. Status: ' + res.getStatusCode() + ', Body: ' + res.getBody());
                throw new CalloutException('Failed to create Payment Method. Status: ' + res.getStatusCode());
            }
        } catch (Exception e) {
            System.debug(
                'Error creating Payment Method for Lead Id: ' +
                    ld.Id +
                    '. Error: ' +
                    e.getMessage() +
                    ' StackTrace: ' +
                    e.getStackTraceString()
            );
            throw e;
        }
    }
    
    @future(callout=true)
    private static void attachPaymentMethod(String stripeCustomerId, String paymentMethodId) {
        try {
            HttpRequest attachReq = new HttpRequest();
            attachReq.setEndpoint(STRIPE_API_URL + '/payment_methods/' + paymentMethodId + '/attach');
            attachReq.setMethod('POST');
            attachReq.setHeader('Authorization', 'Basic ' + EncodingUtil.base64Encode(Blob.valueOf(SECRET_KEY + ':')));
            attachReq.setHeader('Content-Type', 'application/x-www-form-urlencoded');
            attachReq.setBody('customer=' + EncodingUtil.urlEncode(stripeCustomerId, 'UTF-8'));

            HttpResponse attachRes = new Http().send(attachReq);

            if (attachRes.getStatusCode() == 200) {
                System.debug('Attached Payment Method with ID: ' + paymentMethodId + ' to Customer Id: ' + stripeCustomerId);

                return;
            } else {
                System.debug('Failed to attach Payment Method. Status: ' + attachRes.getStatusCode() + ', Body: ' + attachRes.getBody());
                throw new CalloutException('Failed to attach Payment Method. Status: ' + attachRes.getStatusCode());
            }
        } catch (Exception e) {
            System.debug(
                'Error attaching Payment Method with ID: ' +
                    paymentMethodId +
                    ' to Customer Id: ' +
                    stripeCustomerId +
                    '. Error: ' +
                    e.getMessage() +
                    ' StackTrace: ' +
                    e.getStackTraceString()
            );
            throw e;
        }
    }

    @future(callout=true)
    private static void setupACHMandate(String stripeCustomerId, String paymentMethodId) {
        try {
            Long timestamp = DateTime.now().getTime() / 1000;

            HttpRequest intentReq = new HttpRequest();
            intentReq.setEndpoint(STRIPE_API_URL + '/setup_intents');
            intentReq.setMethod('POST');
            intentReq.setHeader('Authorization', 'Basic ' + EncodingUtil.base64Encode(Blob.valueOf(SECRET_KEY + ':')));
            intentReq.setHeader('Content-Type', 'application/x-www-form-urlencoded');

            List<String> intentBodyParams = new List<String>();

            intentBodyParams.add('automatic_payment_methods[enabled]=true');
            intentBodyParams.add('automatic_payment_methods[allow_redirects]=never');
            intentBodyParams.add('confirm=true');
            intentBodyParams.add('customer=' + EncodingUtil.urlEncode(stripeCustomerId, 'UTF-8'));
            intentBodyParams.add('mandate_data[customer_acceptance][type]=offline');
            intentBodyParams.add(
                'mandate_data[customer_acceptance][accepted_at]=' + EncodingUtil.urlEncode(String.valueOf(timestamp), 'UTF-8')
            );
            intentBodyParams.add('payment_method=' + EncodingUtil.urlEncode(paymentMethodId, 'UTF-8'));

            intentReq.setBody(String.join(intentBodyParams, '&'));

            HttpResponse intentRes = new Http().send(intentReq);

            if (intentRes.getStatusCode() == 200) {
                System.debug('Created Setup Intent with ID: ' + intentRes.getBody());
                return;
            } else {
                System.debug('Failed to create Setup Intent. Status: ' + intentRes.getStatusCode() + ', Body: ' + intentRes.getBody());
                throw new CalloutException('Failed to create Setup Intent. Status: ' + intentRes.getStatusCode());
            }
        } catch (Exception e) {
            System.debug(
                'Error setting up ACH Mandate for Payment Method Id: ' +
                    paymentMethodId +
                    ' and Customer Id: ' +
                    stripeCustomerId +
                    '. Error: ' +
                    e.getMessage() +
                    ' StackTrace: ' +
                    e.getStackTraceString()
            );
            throw e;
        }
    }
}