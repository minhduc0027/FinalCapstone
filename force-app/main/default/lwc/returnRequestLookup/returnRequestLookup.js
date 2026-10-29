import { LightningElement, api } from "lwc";
import smartReturnMsg40 from "@salesforce/label/c.SmartReturn_MSG_40";
import smartReturnMsg41 from "@salesforce/label/c.SmartReturn_MSG_41";
import smartReturnMsg90 from "@salesforce/label/c.SmartReturn_MSG_90";

export default class ReturnRequestLookup extends LightningElement {
  @api heading = "Mã yêu cầu";
  @api subtitle =
    "Gồm mã yêu cầu và 4 chữ số cuối của số điện thoại gửi yêu cầu, cách nhau bằng dấu cách. Ví dụ: RR-2610-00001 4567.";
  @api showProducts = false;
  @api guestSitePath;
  lookupValue = "";
  request;
  message = "";
  isLoading = false;
  focusResult = false;

  get submitLabel() {
    return this.isLoading ? "Đang tra cứu…" : "Tra cứu";
  }

  handleInput(event) {
    this.lookupValue = event.target.value;
    event.target.setCustomValidity("");
  }

  async handleSubmit(event) {
    event.preventDefault();
    if (this.isLoading) return;
    const input = this.template.querySelector("lightning-input");
    const proof = this.lookupValue.trim().match(/^(\S{1,80})\s+([0-9]{4})$/);
    input.setCustomValidity(
      this.lookupValue.trim() && !proof
        ? "Vui lòng nhập mã yêu cầu, dấu cách và đúng 4 số cuối số điện thoại. Ví dụ: RR-2610-00001 4567."
        : ""
    );
    input.reportValidity();
    if (!proof || !input.checkValidity()) return;

    this.request = undefined;
    this.message = "";
    this.isLoading = true;
    try {
      if (
        !this.guestSitePath ||
        !/^\/(?:[A-Za-z0-9_-]+\/?)*$/.test(this.guestSitePath)
      ) {
        throw new Error("LOOKUP_CONFIGURATION");
      }
      const siteRoot = this.guestSitePath.replace(/\/$/, "");
      const response = await fetch(
        `${siteRoot}/services/apexrest/smartreturn/v1/portal/lookup`,
        {
          method: "POST",
          credentials: "omit",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            requestNumber: proof[1],
            phoneSuffix: proof[2]
          })
        }
      );
      const result =
        typeof response.json === "function" ? await response.json() : null;
      if (!response.ok) {
        if (result?.outcome === "ERROR" && result.reference) {
          this.message = this.formatMessage(smartReturnMsg90, result.reference);
          return;
        }
        throw new Error("LOOKUP_UNAVAILABLE");
      }
      if (result.outcome === "FOUND" && result.request) {
        this.request = result.request;
        this.focusResult = true;
      } else if (result.outcome === "LOCKED") {
        const minutes = Number(result.retryAfterMinutes);
        this.message =
          Number.isInteger(minutes) && minutes > 0
            ? this.formatMessage(smartReturnMsg41, minutes)
            : "Bạn đã nhập sai quá nhiều lần. Vui lòng thử lại sau.";
      } else if (result.outcome === "NOT_FOUND") {
        this.message = smartReturnMsg40;
      } else {
        throw new Error("LOOKUP_UNAVAILABLE");
      }
    } catch {
      this.message =
        "Không thể tra cứu lúc này. Vui lòng thử lại hoặc liên hệ bộ phận hỗ trợ.";
    } finally {
      this.lookupValue = "";
      this.isLoading = false;
    }
  }

  renderedCallback() {
    if (this.focusResult && this.request) {
      this.focusResult = false;
      this.template.querySelector("c-return-request-summary")?.focusHeading();
    }
  }

  formatMessage(message, value) {
    return message.replace("{0}", String(value));
  }
}
