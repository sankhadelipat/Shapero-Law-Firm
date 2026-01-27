public with sharing class Stripe_PaymentMethodCreate_Queueable implements Queueable, Database.AllowsCallouts {
    
    //private List<Id> leadIds;
    private List<Payment_Method__c> paymentMethods;

    public Stripe_PaymentMethodCreate_Queueable(List<Payment_Method__c> paymentMethods){
        this.paymentMethods = paymentMethods;
    }
    

    public void execute(QueueableContext context) {
    }
}