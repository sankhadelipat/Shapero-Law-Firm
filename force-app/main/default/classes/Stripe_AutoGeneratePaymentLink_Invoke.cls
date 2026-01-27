public class Stripe_AutoGeneratePaymentLink_Invoke {

   

    public class FlowRequest{
        @InvocableVariable(required=true)
        public Id recId;

        @InvocableVariable
        public String leadOrAccount;
    }

    @InvocableMethod(label='Auto Generate Payment Link' description='Generate Payment Link Automatically and update on Invoice')
    public static void create_StripePaymentLink(List<FlowRequest> requests) {

        system.debug('Running- Stripe_AutoGeneratePaymentLink_Invoke.create_StripePaymentLink');
        List<Id> invoiceIds = new List<Id>();
        for(FlowRequest request : requests){
            System.debug('request: ' + request);
            invoiceIds.add(request.recId);
        }

        system.debug('invoiceIds.size(): ' + invoiceIds.size());
        if(!invoiceIds.isEmpty()){
            system.debug('calling queueable class - Stripe_AutoGeneratePaymentLink_Queueable');
            system.enqueueJob(new Stripe_AutoGeneratePaymentLink_Queueable(invoiceIds));
        }
    }
}