/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : ContractToMonthlyIncoiceBatch
 * Author          : Lax
 * Created Date    : Jan 20, 2026
 * Last Modified By: Lax
 * Last Modified On: Jan 20, 2026
 * Description     : This class implements to create monthly retainer invoices from contracts
 *  
 * Change History  :
 *  Date          │   Author     │   Change
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 *  Jan 20, 2026  │ Lax   │ Initial version
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 */

global class ContractToMonthlyIncoiceBatch 
implements Database.Batchable<SObject>, Schedulable {

	global Database.QueryLocator start(Database.BatchableContext bc) {
		return Database.getQueryLocator([
			SELECT Id, AccountId, StartDate, EndDate, Account.PersonContactId, Account.PersonEmail, 
                   Next_Invoice_Date__c, Monthly_Fee__c, Last_Invoice_Date__c
			FROM Contract
			WHERE StartDate <= TODAY
			AND EndDate >= TODAY
			AND Next_Invoice_Date__c = TODAY
			AND Last_Invoice_Date__c != TODAY
			AND Account.IsPersonAccount = true
		]);
	}

	global void execute(Database.BatchableContext bc, List<Contract> scope) {

		System.debug('batch records size--> ' + scope.size());

		try{
			/* --------------------------------
				Create Monthly Retainer Invoices
				------------------------------- */
			
			Date today = Date.today();

			String monthlyRetainerProductName = System.Label.Monthly_Retainer_Product_Name;
			system.debug('System.Label.Monthly_Retainer_Product_Name: ' + System.Label.Monthly_Retainer_Product_Name);
			List<Product2> products = [SELECT Id, Name 
										FROM Product2 
										WHERE Name = :monthlyRetainerProductName];
			System.debug('Found ' + products.size() + ' products matching label: ' + monthlyRetainerProductName);

			List<Invoice__c> invoicesToInsert = new List<Invoice__c>();
			Map<Id, Contract> contractMap = new Map<Id, Contract>();

			Integer contractNum = 0;
			for (Contract c : scope) { 
				contractNum++;
				System.debug('Contract'+contractNum+': '+ c);
				// create invoice
				invoicesToInsert.add(new Invoice__c(
					Contract__c = c.Id,
					Account__c = c.AccountId,
					Invoice_Date__c = Date.today(),
					Status__c = 'Draft',
					Due_Date__c = Date.today().addMonths(1)
				));
				contractMap.put(c.Id, c);
			}

			insert invoicesToInsert;
			system.debug('invoicesToInsert('+ invoicesToInsert.size() + '): ' + invoicesToInsert);

			List<Invoice_Line_Item__c> lineItems = new List<Invoice_Line_Item__c>();

			Integer invNum = 0;
			for (Invoice__c inv : invoicesToInsert) {

				invNum++;
				System.debug('Invoice '+invNum+' for LineItem: '+ inv);

				Contract c = contractMap.get(inv.Contract__c);

				lineItems.add(new Invoice_Line_Item__c(
					Invoice__c = inv.Id,
					Fee_Type__c = products[0].Id,
					Description__c = 'Monthly Retainer Fee',
					Quantity__c = 1,
					Unit_Price__c = c.Monthly_Fee__c,
					Tax_Percentage__c = 0
				));
			}

			insert lineItems;
			system.debug('lineItems('+ lineItems.size() + '): ' + lineItems);

			/* --------------------------------
				Send Emails + Generate PDFs
				------------------------------- */

			List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
			List<Invoice__c> invoicesToUpdate = new List<Invoice__c>();
			List<Contract> contractsToUpdate = new List<Contract>();

			// EmailTemplate template = [
			// 	SELECT Id
			// 	FROM EmailTemplate
			// 	WHERE DeveloperName = 'Monthly_Invoice_Template'
			// 	LIMIT 1
			// ];

			for (Invoice__c inv : invoicesToInsert) {

				system.debug('running for invoice: ' + inv);

				Contract c = contractMap.get(inv.Contract__c);
				system.debug('contract c: ' + c);

				// Safety check
				if (c.Account.PersonContactId == null || c.Account.PersonEmail == null) {
					// invoicesToUpdate.add(
					//     new Invoice__c(Id = inv.Id, Status__c = 'Failed')
					// );
					continue;
				}

				// PageReference pdfPage = Page.InvoicePdfVFpage;
				// pdfPage.getParameters().put('id', inv.Id);
				// Blob pdfBlob = pdfPage.getContentAsPDF();
				// system.debug('pdfBlob: ');
				// system.debug(pdfBlob);

				// Messaging.EmailFileAttachment attachment = new Messaging.EmailFileAttachment();
				// attachment.setFileName(inv.Name + '.pdf');
				// attachment.setBody(pdfBlob);

				Messaging.SingleEmailMessage mail = new Messaging.SingleEmailMessage();

				// mail.setTargetObjectId(
				//     getContactId(inv.Contract__c)
				// );
				// mail.setTemplateId(template.Id);
				// mail.setFileAttachments(
				//     new List<Messaging.EmailFileAttachment>{ attach }
				// );
				// mail.setSaveAsActivity(true);

				mail.setUseSignature(false); 
				mail.setToAddresses(new String[]{'lax@delipat.com'});
				mail.setSubject('Invoice – Monthly Case Fee ' + inv.Name);
				mail.setPlainTextBody('msgBody');
				//mail.setFileAttachments(new Messaging.EmailFileAttachment[]{attachment});

				emails.add(mail);

				// Mark Invoice as Sent
				// invoicesToUpdate.add(
				// 	new Invoice__c(
				// 		Id = inv.Id,
				// 		Status__c = 'Sent'
				// 	)
				// );

				// Update Contract dates
				//Contract c = contractMap.get(inv.Contract__c);
				c.Last_Invoice_Date__c = c.Next_Invoice_Date__c;
				c.Next_Invoice_Date__c = c.Next_Invoice_Date__c.addMonths(1);
				contractsToUpdate.add(c);
			}
			system.debug('end of loop');
			
			if (!emails.isEmpty()) {
				Messaging.sendEmail(emails);
			}

			if (!invoicesToUpdate.isEmpty()) {
				update invoicesToUpdate;
			}

			if (!contractsToUpdate.isEmpty()) {
				update contractsToUpdate;
			}
		} catch(Exception e){
			system.debug('Batch Exception: '+ e.getMessage());
		}
	}

	global void finish(Database.BatchableContext bc) {
		System.debug('Contract invoice batch completed');
	}

	global void execute(SchedulableContext sc) {
        Database.executeBatch(this, 50);
    }
}