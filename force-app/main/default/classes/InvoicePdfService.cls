public class InvoicePdfService {

    @AuraEnabled(cacheable=false)
    public static String getPreviewUrl(Id invoiceId) {
        return '/apex/InvoicePdfVFpage?id=' + invoiceId;
    }

    @AuraEnabled
    public static void sendInvoice(Id invoiceId) {
        try{
            system.debug('SendIvoice from apex is running: ' + invoiceId);

            Invoice__c inv = [
                SELECT Id, Name, Account__c, Account__r.PersonEmail, Account__r.Name,
                Lead__c, Lead__r.Email, Lead__r.Name
                FROM Invoice__c
                WHERE Id = :invoiceId
                LIMIT 1
            ];

            

            String emailTo;
            String clientName;
            String msgBody = 'Please find the attached invoice.';
            // Prefer Person Account email
            if (inv.Account__r != null) {
                if (String.isNotBlank(inv.Account__r.PersonEmail)){
                    emailTo = inv.Account__r.PersonEmail;
                }
                if(String.isNotBlank(inv.Account__r.Name)){
                    clientName = inv.Account__r.Name;
                }

            // Fallback to Lead email
            } else if (inv.Lead__r != null) {
                if(String.isNotBlank(inv.Lead__r.Email)){
                    emailTo = inv.Lead__r.Email;
                }
                if(String.isNotBlank(inv.Lead__r.Name)){
                    clientName = inv.Lead__r.Name;
                }

            // Final fallback (optional)
            } else {
                //clientName = 'Sarah';
                emailTo = 'lax@delipat.com';
                //msgBody = '';
            }
            system.debug('emailTo' + emailTo);
            msgBody = 'Dear '+ clientName +',\n\n' +
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
            pdfPage.getParameters().put('id', invoiceId);

            Blob pdfBlob = pdfPage.getContentAsPDF();

            Messaging.EmailFileAttachment attachment = new Messaging.EmailFileAttachment();
            attachment.setFileName(inv.Name + '.pdf');
            attachment.setBody(pdfBlob);

            Messaging.SingleEmailMessage msg = new Messaging.SingleEmailMessage();
            msg.setUseSignature(false); 
            msg.setToAddresses(new String[]{emailTo});
            msg.setSubject('Invoice – Initial Case Fee ' + inv.Name);
            msg.setPlainTextBody(msgBody);
            msg.setFileAttachments(new Messaging.EmailFileAttachment[]{attachment});

            Messaging.sendEmail(new Messaging.SingleEmailMessage[]{msg});
            system.debug('meaage Sent');
        } catch(Exception e){
            throw new AuraHandledException('Invoice email failed: ' + e.getMessage());
        }
    }

    @AuraEnabled(cacheable=false)
    public static String getInvoiceMessage(Id invoiceId) {
        Invoice__c inv = [
            SELECT Due_Date__c, Status__c
            FROM Invoice__c
            WHERE Id = :invoiceId
            LIMIT 1
        ];

        if (inv.Due_Date__c < Date.today())
            return 'The invoice is past due. Please review before sending.';

        if (inv.Status__c == 'Paid')
            return 'This invoice is already Paid.';

        return 'Invoice is ready to send.';
    }


    // ----------- Bulk Email Sent ------------------
    public class InvoiceRequest {
        @InvocableVariable(required=true)
        public Id invoiceId;
    }

    @InvocableMethod(label='Send Invoice PDFs'
                     description='Send invoice PDFs by email (bulk-safe)')
    public static void sendInvoices(List<InvoiceRequest> requests) {

        if (requests == null || requests.isEmpty()) {
            return;
        }

        Set<Id> invoiceIdSet = new Set<Id>();
        for (InvoiceRequest req : requests) {
            if (req != null && req.invoiceId != null) {
                invoiceIdSet.add(req.invoiceId);
            }
        }

        if (!invoiceIdSet.isEmpty()) {
            System.enqueueJob(
                new SendInvoicePdfQueueable(
                    new List<Id>(invoiceIdSet)
                )
            );
        }
        /* if (requests == null || requests.isEmpty()) {
            return;
        }

        Set<Id> invoiceIds = new Set<Id>();
        for (InvoiceRequest req : requests) {
            if (req != null && req.invoiceId != null) {
                invoiceIds.add(req.invoiceId);
            }
        }
        system.debug('invoiceIds: ' + invoiceIds);

        if (invoiceIds.isEmpty()) {
            return;
        }

        List<Invoice__c> invoices = [
            SELECT Id,
                   Name,
                   Account__c,
                   Lead__c,
                   Account__r.PersonEmail,
                   Lead__r.Email,
                   Stripe_Payment_Link__c

            FROM Invoice__c
            WHERE Id IN :invoiceIds
        ];

        List<Messaging.SingleEmailMessage> emails = new List<Messaging.SingleEmailMessage>();

        system.debug('Invoices: ' + invoices);
        for (Invoice__c inv : invoices) {

            String emailTo = resolveEmail(inv);
            if (String.isBlank(emailTo)) {
                continue; // skip if no email
            }

            PageReference pdfPage = Page.InvoicePdfVFpage;
            pdfPage.getParameters().put('id', inv.Id);

            Blob pdfBlob;
            try {
                pdfBlob = pdfPage.getContentAsPDF();
            } catch (Exception e) {
                System.debug('PDF generation failed for Invoice ' + inv.Id);
                continue;
            }

            Messaging.EmailFileAttachment attachment = new Messaging.EmailFileAttachment();
            attachment.setFileName('Invoice_' + inv.Name + '.pdf');
            attachment.setBody(pdfBlob);

            Messaging.SingleEmailMessage msg = new Messaging.SingleEmailMessage();
            msg.setToAddresses(new String[]{ emailTo });
            msg.setSubject('Invoice ' + inv.Name);
            msg.setPlainTextBody('Please find the attached invoice.');
            msg.setFileAttachments(new Messaging.EmailFileAttachment[]{ attachment });

            emails.add(msg);
        }

        if (!emails.isEmpty()) {
            Messaging.sendEmail(emails);
        } */
    }

    private static String resolveEmail(Invoice__c inv) {

        if (inv.Account__r != null && String.isNotBlank(inv.Account__r.PersonEmail)) {
            return inv.Account__r.PersonEmail;
        }

        if (inv.Lead__r != null && String.isNotBlank(inv.Lead__r.Email)) {
            return inv.Lead__r.Email;
        }

        return 'lax@delipat.com'; // fallback
    }
}