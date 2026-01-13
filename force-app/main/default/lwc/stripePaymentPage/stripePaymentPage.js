import { LightningElement, track, api } from "lwc";
import { loadScript } from "lightning/platformResourceLoader";
import { ShowToastEvent } from "lightning/platformShowToastEvent";

import createPaymentIntent from "@salesforce/apex/StripePaymentIntentService.createPaymentIntent";
import getStripePublishableKey from "@salesforce/apex/StripePaymentIntentService.getStripePublishableKey";

const STRIPE_JS = "https://js.stripe.com/v3/";

export default class StripePaymentPage extends LightningElement {
    @api recordId;
    @track amount;
    @track currencyCode = "usd";
    @track billingName;
    @track billingEmail;

    @track error;
    @track paymentStatus;
    @track isLoading = false;

    // Stripe.js objects
    stripe;
    card;
    elements;
    stripeInitialized = false;

    async renderedCallback() {
        if (this.stripeInitialized) return;

        // Load Stripe.js and fetch publishable key in parallel
        Promise.all([loadScript(this, STRIPE_JS), getStripePublishableKey()])
            .then(([_, publishableKey]) => {
                this.stripeInitialized = true;
                this.stripe = window.Stripe(publishableKey);
                console.log(window.Stripe(publishableKey));
                const elements = this.stripe.elements();
                this.card = elements.create("card", {
                    hidePostalCode: true,
                    style: {
                        base: {
                            fontSize: "16px",
                            color: "#32325d",
                            "::placeholder": { color: "#aab7c4" }
                        },
                        invalid: { color: "#fa755a", iconColor: "#fa755a" }
                    }
                });
                this.card.mount(this.template.querySelector(".card-element"));
            })
            .catch((error) => {
                this.error = "Failed to load Stripe.js: " + error.message;
            });
    }

    handleInputChange(evt) {
        const { name, value } = evt.target;
        // Keep mapping safe and explicit
        if (name === "amount") this.amount = value;
        if (name === "billingName") this.billingName = value;
        if (name === "billingEmail") this.billingEmail = value;
    }

    async handlePay() {
        this.error = null;
        this.paymentStatus = null;
        this.isLoading = true;

        // Basic validation
        if (!this.amount || this.amount <= 0) {
            this.error = "Please enter a valid amount.";
            this.isLoading = false;
            return;
        }

        // 1) Create PaymentIntent on server
        const result = await createPaymentIntent({ amount: this.amount, invoiceId: this.recordId });

        if (!result.success) {
            this.error = "Failed to create payment intent: " + result.errorMessage;
            this.isLoading = false;
            this.dispatchEvent(
                new ShowToastEvent({
                    title: "Error",
                    message: this.error,
                    variant: "error"
                })
            );

            return;
        }

        const { error, paymentIntent } = await this.stripe.confirmCardPayment(result.clientSecret, {
            payment_method: {
                card: this.card
            }
        });

        if (error) {
            this.error = error.message;
        } else if (paymentIntent.status === "succeeded") {
            // alert("Payment successful!");
        }
    }
}