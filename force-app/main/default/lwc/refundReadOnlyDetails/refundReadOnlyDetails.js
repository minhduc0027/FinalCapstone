import { LightningElement, api } from "lwc";

export default class RefundReadOnlyDetails extends LightningElement {
  @api recordId;
  openSections = ["summary", "failure", "reconciliation"];
}
