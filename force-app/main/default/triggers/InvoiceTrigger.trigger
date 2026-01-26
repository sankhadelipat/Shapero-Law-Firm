trigger InvoiceTrigger on Invoice__c(after update) {
	
	/* 
	   Auto Convert Parent Lead of the Invoice
	*/
	//List<Invoice__c> invoicesToProcess = new List<Invoice__c>();
	Set<String> invoiceIds = new Set<String>();
    for (Invoice__c inv : Trigger.new) {
        Invoice__c oldInv = Trigger.oldMap.get(inv.Id);

		system.debug('Is ready to convert parent Lead?'+inv.Id+ ' Status__c: '+inv.Status__c+ ' oldInv.Status__c: '+oldInv.Status__c
						+ ' inv.Lead__c: '+inv.Lead__c + ' inv.Account__c: '+inv.Account__c + ' inv.Convert_Parent_Lead__c: '+inv.Convert_Parent_Lead__c);
        if (
            inv.Status__c == 'Paid'
            && oldInv.Status__c != 'Paid'
            && inv.Lead__c != null
            && inv.Account__c == null
            && inv.Convert_Parent_Lead__c == true
        ) {
            //invoicesToProcess.add(inv);
			invoiceIds.add((String)inv.Id);
        }
    }

    if (!invoiceIds.isEmpty()) {
        InvoiceLeadConversionService.convertLeadsFromInvoices(invoiceIds);
    }
	// --------------------------------------------------------------------------
}