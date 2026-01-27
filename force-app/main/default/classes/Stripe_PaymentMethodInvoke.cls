public class Stripe_PaymentMethodInvoke {

    public class FlowRequest {
        @InvocableVariable(required=true)
        public Id recId;

        @InvocableVariable
        public String objectName;
    }


    @InvocableMethod(label='Create Payment Method' description='Create Payment Method on Stripe')
    public static void create_StripePaymentMethod(List<FlowRequest> requests) {
        
        List<Id> leadIds = new List<Id>();

        for(FlowRequest request : requests){
            System.debug('request: ' + request);
            if(request.objectName == 'Lead'){
                leadIds.add(request.recId);
            }
        }
        
        // when stripe customer created from lead pass payment methods from here
        if(!leadIds.isEmpty()){
            List<Payment_Method__c> paymentMethods = [SELECT Id, Lead__c, Stripe_Payment_Method_Id__c, Payment_Method__c 
                                                    FROM Payment_Method__c 
                                                    WHERE Lead__c IN :leadIds
                                                    AND Stripe_Payment_Method_Id__c = NULL];
            system.debug('calling ');
            if(!paymentMethods.isEmpty()){
                System.enqueueJob(new Stripe_PaymentMethodCreate_Queueable(paymentMethods));
            }
        }

    }
}