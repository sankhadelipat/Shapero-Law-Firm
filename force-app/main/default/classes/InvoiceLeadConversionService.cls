/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : InvoiceLeadConversionService
 * Author          : Lax
 * Created Date    : Jan 5, 2026
 * Last Modified By: Lax
 * Last Modified On: Jan 5, 2026
 * Description     : This class implements for......
 *  
 * Change History  :
 *  Date          │   Author     │   Change
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 *  Jan 5, 2026  │ Lax   │ Initial version
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 */

public class InvoiceLeadConversionService {

	//@future
	public static void convertLeadsFromInvoices(Set<String> invoiceIds) {

		system.debug('Running InvoiceLeadConversionService.convertLeadsFromInvoices(Set<String>)');
		List<Invoice__c> invoices = [
            SELECT Id, Lead__c
            FROM Invoice__c
            WHERE Id IN :invoiceIds
        ];
		system.debug('invoices: ' + invoices);
        // Collect Lead Ids
        Set<Id> leadIds = new Set<Id>();
        for (Invoice__c inv : invoices) {
            leadIds.add(inv.Lead__c);
        }

        // Query Leads
        Map<Id, Lead> leadMap = new Map<Id, Lead>(
            [SELECT Id, IsConverted
             FROM Lead
             WHERE Id IN :leadIds]
        );

        // Prepare Lead Converts
        List<Database.LeadConvert> converts = new List<Database.LeadConvert>();

		String convertedStatus = getConvertedStatus();
        for (Id leadId : leadIds) {
            Lead l = leadMap.get(leadId);
            if (l != null && !l.IsConverted) {
                Database.LeadConvert lc = new Database.LeadConvert();
                lc.setLeadId(leadId);
                lc.setConvertedStatus(convertedStatus);
                lc.setDoNotCreateOpportunity(false);
                converts.add(lc);
            }
        }

        // Convert Leads
        if (!converts.isEmpty()) {
            Database.convertLead(converts, false);
        }
		//UpdateParentAccountsOfLeadsChildObject.updateChildObjects(leadIds);
		/*
        // Re-query converted leads to get Account IDs
        Map<Id, Lead> convertedLeads = new Map<Id, Lead>(
            [SELECT Id, ConvertedAccountId
             FROM Lead
             WHERE Id IN :leadIds
             AND IsConverted = true]
        );

        // Update ALL invoices for those leads
        List<Invoice__c> invoicesToUpdate = [
            SELECT Id, Lead__c, Account__c
            FROM Invoice__c
            WHERE Lead__c IN :leadIds
        ];

        for (Invoice__c inv : invoicesToUpdate) {
            Lead l = convertedLeads.get(inv.Lead__c);
            if (l != null && l.ConvertedAccountId != null) {
                inv.Account__c = l.ConvertedAccountId;
            }
        }

        if (!invoicesToUpdate.isEmpty()) {
            update invoicesToUpdate;
        }
		*/
    }

    // Fetch a valid converted status dynamically
    private static String getConvertedStatus() {
        return [
            SELECT MasterLabel
            FROM LeadStatus
            WHERE IsConverted = true
            LIMIT 1
        ].MasterLabel;
    }

}