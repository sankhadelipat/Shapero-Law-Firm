trigger ExpenseT on Expense__c (after update) {
    List<Id> approvedIds = new List<Id>();

    for (Expense__c e : Trigger.new) {
        Expense__c oldE = Trigger.oldMap.get(e.Id);

        if (
            e.Status__c == 'Approved' &&
            oldE.Status__c != 'Approved' &&
            !String.isBlank(e.QBO_Expense_Id__c)
        ) {
            approvedIds.add(e.Id);
        }
    }

    if (!approvedIds.isEmpty()) {
        QBOExpenseStatusApprove.updateBillableStatus(approvedIds);
    }
}