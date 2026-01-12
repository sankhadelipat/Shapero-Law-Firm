trigger LeadAfterAttachingCustomerId on Lead(after update) {
    // List<Id> leadsToProcess = new List<Id>();

    // for (Lead newLead : Trigger.new) {
    //     Lead oldLead = Trigger.oldMap.get(newLead.Id);

    //     Boolean statusJustSigned = newLead.Status == 'Retainer Signed' && oldLead.Status != 'Retainer Signed';

    //     Boolean stripeNowPresent = String.isNotBlank(newLead.Stripe_Customer_ID__c) && String.isBlank(oldLead.Stripe_Customer_ID__c);

    //     if (
    //         newLead.Status == 'Retainer Signed' &&
    //         String.isNotBlank(newLead.Stripe_Customer_ID__c) &&
    //         (statusJustSigned || stripeNowPresent)
    //     ) {
    //         leadsToProcess.add(newLead.Id);
    //     }
    // }

    // if (!leadsToProcess.isEmpty()) {
    //     System.enqueueJob(new PaymentMethodCreateQueueable(leadsToProcess));
    // }
}