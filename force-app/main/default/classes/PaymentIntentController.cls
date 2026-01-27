public with sharing class PaymentIntentController {

    @AuraEnabled
    public static String pushToQuickBooks(Id paymentIntentId) {
        Payment_Intent__c pi = [
            SELECT Id,
                   Status__c,
                   Amount__c,
                   QBO_Payment_ID__c,
                   Account__r.QBO_Customer_Id__c,
                   Invoice__r.QBO_Invoice_Id__c
            FROM Payment_Intent__c
            WHERE Id = :paymentIntentId
            LIMIT 1
        ];

        if (pi.QBO_Payment_ID__c != null) {
            throw new AuraHandledException(
                'Payment already synced to QuickBooks.'
            );
        }

        if (pi.Status__c != 'Succeeded' && pi.Status__c != 'Succeed') {
            throw new AuraHandledException(
                'Only payments with status "Succeeded" can be pushed.'
            );
        }

        String qboPaymentId = QBO_PaymentPushService.pushPaymentToQBO(pi);

        pi.QBO_Payment_ID__c = qboPaymentId;
        pi.Status__c = 'Paid';
        update pi;

        return qboPaymentId;
    }
}