trigger LeadTrigger on Lead (after update) {

    if(trigger.isUpdate && trigger.isAfter){
        system.debug('running after update trigger');

        List<Id> leadsToCreateStripeCustomer = New List<Id>();
        List<Id> leadIdsWithPaymentMethods = New List<Id>();

        for(Lead newLead: Trigger.new){
            Lead oldLead = Trigger.oldMap.get(newLead.Id);
            
            // Status changed to Retainer Signed - then create stripe customers
            if(newLead.Status == 'Retainer Signed'  && oldLead.Status != 'Retainer Signed' && newLead.Stripe_Customer_ID__c == null){
        		leadsToCreateStripeCustomer.add(newLead.Id);
            }

            // Stripe Customer ID added to lead - then create a stripe Payment Method
            /*if(newLead.Status == 'Retainer Signed' && newLead.Stripe_Customer_ID__c != null && oldLead.Stripe_Customer_ID__c == null){
                leadIdsWithPaymentMethods.add(newLead.Id);
            }*/
        }

        System.debug('leadsToCreateStripeCustomer: ' + leadsToCreateStripeCustomer.size() + ' ' + leadsToCreateStripeCustomer );
        If(!leadsToCreateStripeCustomer.isEmpty()){
            system.debug('calling Stripe_CustomerCreate.createStripeCustomer');
            System.enqueueJob(new Stripe_CustomerCreate(leadsToCreateStripeCustomer));
        }

        /*System.debug('leadIdsWithPaymentMethods: ' + leadIdsWithPaymentMethods.size() + ' ' + leadIdsWithPaymentMethods );
        If(!leadIdsWithPaymentMethods.isEmpty()){

            //List<Id> pmIds = new List<Id>();
            List<Payment_Method__c> paymentMethods = [SELECT Id, Lead__c, Stripe_Payment_Method_Id__c 
                                                    FROM Payment_Method__c 
                                                    WHERE Lead__c IN :leadIdsWithPaymentMethods
                                                    AND Stripe_Payment_Method_Id__c = NULL];
            system.debug('calling ');
            if(!paymentMethods.isEmpty()){
                System.enqueueJob(new Stripe_PaymentMethodCreate_Queueable(paymentMethods));
            }
            
        } */



        /*
            When Lead Converted
        */
        Set<Id> convertedLeadIds = new Set<Id>();

        for (Lead l : Trigger.new) {
            Lead oldLead = Trigger.oldMap.get(l.Id);

            if (
                l.IsConverted &&
                !oldLead.IsConverted &&
                l.ConvertedAccountId != null
            ) {
                convertedLeadIds.add(l.Id);
            }
        }

        if (!convertedLeadIds.isEmpty()) {
            LeadPostConversionService.updateChildObjects(convertedLeadIds);
        }
    }
     
}