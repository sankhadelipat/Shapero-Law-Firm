trigger ContractTrigger on Contract(after insert) {
    if (Trigger.isAfter && Trigger.isInsert) {
        Set<Id> retainerContractIds = new Set<Id>();

        for (Contract con : Trigger.new) {
            if (con.Contract_Type__c == 'Retainer' && con.StartDate != null && con.Monthly_Fee__c != null) {
                retainerContractIds.add(con.Id);
            }
        }
        ContractService.generateInitialRetainerInvoices(retainerContractIds);
    }
}