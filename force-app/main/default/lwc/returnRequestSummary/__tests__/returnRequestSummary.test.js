import { createElement } from "lwc";
import ReturnRequestSummary from "c/returnRequestSummary";

describe("customer return summary", () => {
  afterEach(() => {
    document.body.replaceChildren();
  });

  it("does not render money in guest mode even if a caller supplies it", () => {
    const element = createElement("c-return-request-summary", {
      is: ReturnRequestSummary
    });
    element.request = {
      requestNumber: "RR-2610-00001",
      status: "COMPLETED",
      refundAmount: 1992000,
      amountKind: "ACTUAL",
      lines: [],
      history: []
    };
    document.body.appendChild(element);
    expect(
      element.shadowRoot.querySelector('[data-section="amount"]')
    ).toBeNull();
  });

  it("keeps an unsuccessful refund separate from payment completion", () => {
    const element = createElement("c-return-request-summary", {
      is: ReturnRequestSummary
    });
    element.showAmount = true;
    element.request = {
      requestNumber: "RR-2610-00001",
      status: "REFUND_FAILED",
      refundAmount: 1992000,
      amountKind: "ACTUAL",
      lines: [],
      history: []
    };
    document.body.appendChild(element);
    expect(element.shadowRoot.querySelector("lightning-badge").label).toBe(
      "Hoàn tiền chưa thành công"
    );
    expect(
      element.shadowRoot.querySelector('[data-section="amount"] dt').textContent
    ).toBe("Số tiền hoàn thực tế");
  });
});
