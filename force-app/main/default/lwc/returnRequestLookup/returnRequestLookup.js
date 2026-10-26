import { LightningElement, api } from "lwc";

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
          credentials: "same-origin",
          headers: { "Content-Type": "application/json" },
          body: JSON.stringify({
            requestNumber: proof[1],
            phoneSuffix: proof[2]
          })
        }
      );
      if (!response.ok) throw new Error("LOOKUP_UNAVAILABLE");
      const result = await response.json();
      if (result.outcome === "FOUND" && result.request) {
        this.request = result.request;
        this.focusResult = true;
      } else if (result.outcome === "LOCKED") {
        const minutes = Number(result.retryAfterMinutes);
        this.message =
          Number.isInteger(minutes) && minutes > 0
            ? `Bạn đã nhập sai quá nhiều lần. Vui lòng thử lại sau ${minutes} phút.`
            : "Bạn đã nhập sai quá nhiều lần. Vui lòng thử lại sau.";
      } else if (result.outcome === "NOT_FOUND") {
        this.message =
          "Không tìm thấy yêu cầu phù hợp. Vui lòng kiểm tra lại mã yêu cầu và số điện thoại.";
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
}
