import { LightningElement, api } from "lwc";

export default class ApprovalRejectModal extends LightningElement {
  @api selectedCount = 0;
  reason = "";
  staffNote = "";
  isSubmitting = false;

  get title() {
    return `Reject ${this.selectedCount} request(s)`;
  }

  handleChange(event) {
    this[event.target.dataset.field] = event.target.value;
  }

  handleCancel() {
    this.dispatchEvent(new CustomEvent("cancel"));
  }

  handleSubmit() {
    const reasonInput = this.template.querySelector('[data-field="reason"]');
    reasonInput.setCustomValidity("");
    if (!this.reason?.trim()) {
      reasonInput.setCustomValidity("Rejection reason is required.");
      reasonInput.reportValidity();
      return;
    }
    this.dispatchEvent(
      new CustomEvent("submit", {
        detail: {
          reason: this.reason.trim(),
          staffNote: this.staffNote?.trim() || null
        }
      })
    );
  }

  handleKeydown(event) {
    if (event.key === "Escape") this.handleCancel();
  }
}
