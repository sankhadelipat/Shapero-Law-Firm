/**
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 * Class Name      : SendInvoicePdfQueueable
 * Author          : Lax
 * Created Date    : Jan 6, 2026
 * Last Modified By: Lax
 * Last Modified On: Jan 6, 2026
 * Description     : This class implements to sent bulk email to customers with invoices
 *
 * Change History  :
 *  Date          │   Author     │   Change
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 *  Jan 6, 2026  │ Lax   │ Initial version
 * ――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――――
 */

public class SendInvoicePdfQueueable implements Queueable, Database.AllowsCallouts {
    private Map<Id, String> invoiceIdToTypeMap;

    public SendInvoicePdfQueueable(Map<Id, String> invoiceIdToTypeMap) {
        this.invoiceIdToTypeMap = invoiceIdToTypeMap;
    }

    public void execute(QueueableContext context) {
        System.debug('SendInvoicePdfQueueable - invoiceIdToTypeMap: ' + invoiceIdToTypeMap);

        if (invoiceIdToTypeMap == null || invoiceIdToTypeMap.isEmpty()) {
            return;
        }

        // -----------------------------
        // Load invoices + recipients
        // -----------------------------
        List<Invoice__c> invoices = [
            SELECT
                Id,
                Name,
                Account__c,
                Account__r.PersonContactId,
                Account__r.PersonEmail,
                Account__r.Name,
                Lead__c,
                Lead__r.Email,
                Lead__r.Name,
                Stripe_Payment_Link__c
            FROM Invoice__c
            WHERE Id IN :invoiceIdToTypeMap.keySet()
        ];
        system.debug('Invoices: ' + invoices);

        // -----------------------------
        // Load templates once
        // -----------------------------
        Map<String, Id> templateByType = new Map<String, Id>();

        List<EmailTemplate> templates = [
            SELECT Id, DeveloperName
            FROM EmailTemplate
            WHERE DeveloperName IN ('Initial_Invoice_Template', 'Monthly_Invoice_Template')
        ];

        for (EmailTemplate et : templates) {
            if (et.DeveloperName == 'Initial_Invoice_Template') {
                templateByType.put('initial', et.Id);
            } else if (et.DeveloperName == 'Monthly_Invoice_Template') {
                templateByType.put('monthly', et.Id);
            }
        }
        system.debug('templateByType: ' + templateByType);

        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();
        Set<Id> emailedInvoiceIds = new Set<Id>();

        for (Invoice__c inv : invoices) {
            String invType = invoiceIdToTypeMap.get(inv.Id);
            if (String.isBlank(invType))
                continue;

            // -----------------------------
            // Resolve recipient
            // -----------------------------
            Id targetObjectId;
            String emailAddress;

            if (invType == 'initial') {
                if (inv.Lead__c != null && inv.Lead__r.Email != null) {
                    targetObjectId = inv.Lead__c;
                    emailAddress = inv.Lead__r.Email;
                }
            } else if (invType == 'monthly') {
                if (inv.Account__r.PersonContactId != null && inv.Account__r.PersonEmail != null) {
                    targetObjectId = inv.Account__r.PersonContactId;
                    emailAddress = inv.Account__r.PersonEmail;
                }
            }

            if (targetObjectId == null || String.isBlank(emailAddress)) {
                System.debug('No recipient found for Invoice ' + inv.Id);
                continue; // skip if no recipient
            }

            // -----------------------------
            // Resolve template
            // -----------------------------
            Id templateId = templateByType.get(invType);

            if (templateId == null) {
                System.debug('No email template found for type: ' + invType);
                continue; // skip if no template
            }

            // -----------------------------
            // Render PDF
            // -----------------------------
            PageReference pdfPage = Page.InvoicePdfVFpage;
            pdfPage.getParameters().put('id', inv.Id);

            Blob pdfBlob;
            try {
                pdfBlob = pdfPage.getContentAsPDF();
            } catch (Exception e) {
                System.debug('PDF generation failed for Invoice ' + inv.Id + ': ' + e.getMessage());
                continue;
            }

            // -----------------------------
            // Build email
            // -----------------------------
            Messaging.EmailFileAttachment attachment = new Messaging.EmailFileAttachment();
            attachment.setFileName('Invoice_' + inv.Name + '.pdf');
            attachment.setBody(pdfBlob);

            Messaging.SingleEmailMessage msg = new Messaging.SingleEmailMessage();
            msg.setTemplateId(templateId);
            msg.setTargetObjectId(targetObjectId);
            msg.setWhatId(inv.Id);
            msg.setSaveAsActivity(false);
            msg.setUseSignature(true);
            // msg.setToAddresses(new List<String>{ emailAddress });
            // msg.setSubject('Invoice ' + inv.Name);
            // msg.setPlainTextBody(msgBody);
            msg.setFileAttachments(new List<Messaging.EmailFileAttachment>{ attachment });

            emails.add(msg);
            emailedInvoiceIds.add(inv.Id);
        }

        System.debug('emails: ' + emails);
        if (!emails.isEmpty()) {
            try {
                Messaging.sendEmail(emails);

                // -------------------------
                // UPDATE STATUS → SENT
                // -------------------------
                List<Invoice__c> invoicesToUpdate = new List<Invoice__c>();
                for (Id invId : emailedInvoiceIds) {
                    invoicesToUpdate.add(new Invoice__c(Id = invId, Status__c = 'Sent'));
                }

                if (!invoicesToUpdate.isEmpty()) {
                    update invoicesToUpdate;
                }
            } catch (Exception e) {
                System.debug('Email sending failed: ' + e.getMessage());
            }
        }
    }
}