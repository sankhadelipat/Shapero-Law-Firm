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
	private List<Id> invoiceIds;

    public SendInvoicePdfQueueable(List<Id> invoiceIds) {
        this.invoiceIds = invoiceIds;
    }

    public void execute(QueueableContext context) {

		system.debug('SendInvoicePdfQueueable - invoiceIds: ' + invoiceIds);
        if (invoiceIds == null || invoiceIds.isEmpty()) {
            return;
        }

        List<Invoice__c> invoices = [
            SELECT Id,
                   Name,
                   Account__c,
                   Account__r.PersonEmail,
                   Account__r.Name,
                   Lead__c,
                   Lead__r.Email,
                   Lead__r.Name,
                   Stripe_Payment_Link__c
            FROM Invoice__c
            WHERE Id IN :invoiceIds
        ];
		system.debug('Invoices: ' + invoices);


        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();

        for (Invoice__c inv : invoices) {
			system.debug('inv.Stripe_Payment_Link__c: ' + inv.Stripe_Payment_Link__c);

            String emailTo = resolveEmail(inv);
            if (String.isBlank(emailTo)) {
                continue;
            }

            String clientName = resolveName(inv);
            String msgBody = 'Dear '+ clientName +',\n\n' +
                    'We hope this message finds you well.\n\n' +
                    'Please find attached the invoice for the initial case fee related to your engagement with our firm. ' +
                    'For your convenience, a secure payment link is included directly within the attached invoice PDF.\n\n' +
                    'Once payment is completed, you will receive an automatic confirmation. ' +
                    'If you have any questions regarding the invoice or need assistance with the payment, ' +
                    'please feel free to contact us.\n\n' +
                    'We appreciate your prompt attention and look forward to working with you.\n\n\n' + 
                    'Warm Regards,\n' + 
                    'Sarah Shapero\n' + 
                    'Shapero Lawfirm';

            PageReference pdfPage = Page.InvoicePdfVFpage;
            pdfPage.getParameters().put('id', inv.Id);

            Blob pdfBlob;
            try {
                pdfBlob = pdfPage.getContentAsPDF();
            } catch (Exception e) {
                System.debug('PDF generation failed for Invoice ' + inv.Id + ': ' + e.getMessage());
                continue;
            }

            Messaging.EmailFileAttachment attachment = new Messaging.EmailFileAttachment();
            attachment.setFileName('Invoice_' + inv.Name + '.pdf');
            attachment.setBody(pdfBlob);

            Messaging.SingleEmailMessage msg = new Messaging.SingleEmailMessage();
            msg.setUseSignature(false); // DISABLE THE SIGNATURE HERE
            msg.setToAddresses(new String[]{ emailTo });
            msg.setSubject('Invoice ' + inv.Name);
            msg.setPlainTextBody(msgBody);
            msg.setFileAttachments(
                new Messaging.EmailFileAttachment[]{ attachment }
            );

            emails.add(msg);
        }

		system.debug('emails: ' + emails);
        if (!emails.isEmpty()) {
            Messaging.sendEmail(emails);
        }
    }

    private static String resolveEmail(Invoice__c inv) {

        if (inv.Account__r != null && String.isNotBlank(inv.Account__r.PersonEmail)) {
            return inv.Account__r.PersonEmail;
        }

        if (inv.Lead__r != null && String.isNotBlank(inv.Lead__r.Email)) {
            return inv.Lead__r.Email;
        }

        return 'lax@delipat.com';
    }
    private static String resolveName(Invoice__c inv) {

        if (inv.Account__r != null && String.isNotBlank(inv.Account__r.Name)) {
            return inv.Account__r.Name;
        } 
        else if (inv.Lead__r != null && String.isNotBlank(inv.Lead__r.Name)) {
            return inv.Lead__r.Name;
        }

        return '';
    }
}