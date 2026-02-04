/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : InvoiceSyncInvocable
 * Author          : <YourName>
 * Created Date    : Feb 2, 2026
 * Last Modified By: <YourName>
 * Last Modified On: Feb 2, 2026
 * Description     : This class implements for......
 *  
 * Change History  :
 *  Date          │   Author     │   Change
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 *  Feb 2, 2026  │ <YourName>   │ Initial version
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 */

public class OldInvoiceSyncQBOInvocable {

	public class InvoiceRequest {
        @InvocableVariable(required=true label='Account Id' description='used to query the invoices not synced with QBO')
        public Id acccId;

        
    }

    @InvocableMethod(label='Sync Old Invoices to QBo' description='Sync invoices linked with leads')
    public static void sendInvoices(List<InvoiceRequest> requests) {
		if (requests == null || requests.isEmpty())
            return;

        Set<Id> acccIds = New Set<Id>();

        for (InvoiceRequest req : requests) {
            if (req != null && req.acccId != null) {
                acccIds.add(req.acccId);
            }
        }

		system.debug('acccIds in OldInvoiceSyncQBOInvocable: ' + acccIds);
		Account acc = [SELECT Id, QBO_Customer_ID__c FROM Account WHERE Id IN :acccIds LIMIT 1]; 
		system.debug('acc in OldInvoiceSyncQBOInvocable: ' + acc);
        if (!acccIds.isEmpty()){
			List<Invoice__c> invList = [SELECT Id, QBO_Invoice_ID__c, Account__c 
									FROM Invoice__c 
									WHERE Account__c IN:acccIds AND QBO_Invoice_ID__c = null];
			system.debug('list of Invoices: '+ invList);

			Set<Id> invoiceIds = new Set<Id>();
			for(Invoice__c inv: invList){
				invoiceIds.add(inv.Id);
			}
			
			
			system.debug('list of Invoice Ids: '+ invoiceIds);
			if(!invoiceIds.isEmpty()){
            	QuickBooksInvoiceService.createInvoiceAuto(invoiceIds, false);
			}
        }

		
	}

}