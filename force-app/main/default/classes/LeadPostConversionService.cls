/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : LeadPostConversionService
 * Author          : Lax
 * Created Date    : Jan 6, 2026
 * Last Modified By: Lax
 * Last Modified On: Jan 6, 2026
 * Description     : This class implements to update the parent account of invoices from null to converted lead
 *
 * Change History  :
 *  Date          │   Author     │   Change
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 *  Jan 6, 2026  │ Lax   │ Initial version
 *  Jan 19, 2026 | Lax | Create Contract After Conversion and store contract Id on Invoice
 *  Jan 20, 2026 | Lax | Update more informations on contract
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 */

public class LeadPostConversionService {
    @Future
    public static void updateChildObjects(Set<Id> leadIds) {
        Map<Id, Lead> convertedLeads = new Map<Id, Lead>(
            [
                SELECT
                    Id,
                    ConvertedAccountId,
                    Number_Of_Terms__c,
                    Retainer_Signed_Date__c,
                    Retainer_Sent_Date__c,
                    Initial_Fee__c,
                    Monthly_Fee__c,
                    Fee_Type__c
                FROM Lead
                WHERE Id IN :leadIds AND IsConverted = TRUE
            ]
        );

        /* ----------------------------------------------------
            CREATE CONTRACTS
        ---------------------------------------------------- */

        Map<Id, Contract> leadToContractMap = new Map<Id, Contract>();
        List<Contract> contractsToInsert = new List<Contract>();

        for (Lead l : convertedLeads.values()) {
            if (l.ConvertedAccountId == null) {
                continue;
            }

            Date retainerSentDate = l.Retainer_Sent_Date__c != null ? l.Retainer_Sent_Date__c : Date.today();
            Date retainerSignedDate = l.Retainer_Signed_Date__c != null ? l.Retainer_Signed_Date__c : Date.today();
            Date todayDate = Date.today();

            system.debug('l.Retainer_Sent_Date__c--> ' + retainerSentDate);
            system.debug('l.Retainer_Signed_Date__c--> ' + retainerSignedDate);
            // system.debug('l.Number_Of_Terms__c.intValue()--> ' + l.Number_Of_Terms__c.intValue());

            Contract c = new Contract();
            c.AccountId = l.ConvertedAccountId;
            c.Retainer_Sent_Date__c = l.Retainer_Sent_Date__c;
            c.CustomerSignedDate = retainerSignedDate;
            c.StartDate = todayDate;
            // if (l.Number_Of_Terms__c != null) {
            //     c.ContractTerm = l.Number_Of_Terms__c.intValue();
            //     c.EndDate = todayDate.addMonths(l.Number_Of_Terms__c.intValue());
            // }
            c.Initial_Fee__c = l.Initial_Fee__c ?? 0;
            c.Monthly_Fee__c = l.Monthly_Fee__c ?? 0;
            c.Contract_Type__c = l.Fee_Type__c;
            // add other fields

            contractsToInsert.add(c);
            leadToContractMap.put(l.Id, c);
        }
        if (!contractsToInsert.isEmpty()) {
            insert contractsToInsert;
        }

        /* ----------------------------------------------------
            Update Invoices
        ---------------------------------------------------- */

        // Update ALL invoices for those leads
        List<Invoice__c> invoicesToUpdate = [
            SELECT Id, Lead__c, Account__c
            FROM Invoice__c
            WHERE Lead__c IN :leadIds
        ];

        List<Id> invoiceIds = new List<Id>();
        if (!invoicesToUpdate.isEmpty()) {
            for (Invoice__c inv : invoicesToUpdate) {
                Lead l = convertedLeads.get(inv.Lead__c);
                Contract c = leadToContractMap.get(inv.Lead__c);
                if (l != null && l.ConvertedAccountId != null) {
                    inv.Account__c = l.ConvertedAccountId;
                    invoiceIds.add(inv.Id);
                }
                if (c != null) {
                    inv.Contract__c = c.Id;
                }
            }
            update invoicesToUpdate;
        }
        // if (!invoicesToUpdate.isEmpty()) {
        //     update invoicesToUpdate;
        // }

        /* ----------------------------------------------------
            Update Payment Methods
        ---------------------------------------------------- */

        // Update ALL invoices for those leads
        List<Payment_Method__c> pmsToUpdate = [
            SELECT Id, Lead__c, Account__c
            FROM Payment_Method__c
            WHERE Lead__c IN :leadIds
        ];

        if (!pmsToUpdate.isEmpty()) {
            for (Payment_Method__c pm : pmsToUpdate) {
                Lead l = convertedLeads.get(pm.Lead__c);
                if (l != null && l.ConvertedAccountId != null) {
                    pm.Account__c = l.ConvertedAccountId;
                }
            }
            update pmsToUpdate;
        }

        /* ----------------------------------------------------
            Update Payment Intent
        ---------------------------------------------------- */

        if (invoiceIds != null && !invoiceIds.isEmpty()) {
            List<Payment_Intent__c> paymentToUpdate = [
                SELECT Id, Account__c, Invoice__c, Invoice__r.Account__c
                FROM Payment_Intent__c
                WHERE Invoice__c IN :invoiceIds
            ];

            for (Payment_Intent__c pi : paymentToUpdate) {
                pi.Account__c = pi.Invoice__r.Account__c;
            }
            if (!paymentToUpdate.isEmpty()) {
                update paymentToUpdate;
            }
        }
    }
}