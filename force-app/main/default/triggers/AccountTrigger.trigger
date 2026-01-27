trigger AccountTrigger on Account (after insert) {
    if (Trigger.isAfter && Trigger.isInsert) {
        List<Id> accountIds = new List<Id>();
        for (Account acc : Trigger.new) {
            accountIds.add(acc.Id);
        }
        QuickBooksCustomerService.createCustomers(accountIds);
    }
}