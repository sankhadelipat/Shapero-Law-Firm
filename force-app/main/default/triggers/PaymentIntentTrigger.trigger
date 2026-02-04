trigger PaymentIntentTrigger on Payment_Intent__c (after insert) {
  system.debug('running payment intent trigger');
    QBO_PaymentIntentQueueable.enqueue(
        Trigger.new
    ); 
    TestDebugClass.doSomething();
}