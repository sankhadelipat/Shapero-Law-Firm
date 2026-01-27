public class Stripe_CustomerCreate implements Queueable, Database.AllowsCallouts {
    private static final StripeAuth__c STRIPE_AUTH = StripeAuth__c.getOrgDefaults();
    private static final String STRIPE_API_URL = STRIPE_AUTH.API_URL__c;
    private static final String SECRET_KEY = STRIPE_AUTH.SECRET_KEY__c;

    private List<Id> leadIds;

    public Stripe_CustomerCreate(List<Id> leadIds) {
        this.leadIds = leadIds;
    }

    public void execute(QueueableContext context) {
        try {
            List<Lead> leads = [
                SELECT Id, Name, Phone, Email, Status, Stripe_Customer_ID__c
                FROM Lead
                WHERE Id IN :leadIds AND Stripe_Customer_ID__c = NULL
            ];
            if (leads.isEmpty())
                return;

            List<Lead> leadsToUpdate = new List<Lead>();

            for (Lead l : leads) {
                String stripeCustomerId = createStripeCustomer(l);
                if (stripeCustomerId != null) {
                    l.Stripe_Customer_ID__c = stripeCustomerId;
                    leadsToUpdate.add(l);
                }
            }

            if (!leadsToUpdate.isEmpty()) {
                update leadsToUpdate;
            }
        } catch (Exception e) {
            system.debug('Error while Processing lead: ' + e.getMessage());
        }
    }

    public static String createStripeCustomer(Lead lead) {
        Http http = new Http();
        HttpRequest req = new HttpRequest();

        req.setEndpoint('https://api.stripe.com/v1/customers');
        req.setMethod('POST');
        req.setHeader('Authorization', 'Basic ' + EncodingUtil.base64Encode(Blob.valueOf(SECRET_KEY + ':')));
        req.setHeader('Content-Type', 'application/x-www-form-urlencoded');

        // Generate Request Body for Callout
        String requestBody = generateRequestBody(lead);
        system.debug('requestBody--> ' + requestBody);
        req.setBody(requestBody);

        HttpResponse res = http.send(req);
        system.debug('res.getStatusCode()--> ' + res.getStatusCode());

        if (res.getStatusCode() == 200) {
            Map<String, Object> responseMap = (Map<String, Object>) JSON.deserializeUntyped(res.getBody());
            String stripeCustomerId = (String) responseMap.get('id');
            return stripeCustomerId;
        } else {
            system.debug('Failed to create Customer for ' + lead.Name + ': ' + res.getBody());
            return null;
        }
    }

    private static string generateRequestBody(Lead lead) {
        Map<String, String> params = new Map<String, String>{ 'name' => lead.Name, 'metadata[Lead_Id]' => lead.Id };

        if (String.isNotBlank(lead.Phone)) {
            params.put('phone', lead.Phone);
        }
        if (String.isNotBlank(lead.Email)) {
            params.put('email', lead.Email);
        }

        List<String> bodyParts = new List<String>();
        for (String key : params.keySet()) {
            bodyParts.add(EncodingUtil.urlEncode(key, 'UTF-8') + '=' + EncodingUtil.urlEncode(params.get(key), 'UTF-8'));
        }

        return String.join(bodyParts, '&');
    }
}