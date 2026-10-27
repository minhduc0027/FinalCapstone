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

  it("shows the rejected customer request reason as plain text", () => {
    const element = createElement("c-return-request-summary", {
      is: ReturnRequestSummary
    });
    element.request = {
      status: "REJECTED",
      rejectionReason: "Quá thời hạn đổi trả.\n<script>alert('test')</script>"
    };
    document.body.appendChild(element);
    const section = element.shadowRoot.querySelector(
      '[data-section="rejection-reason"]'
    );
    expect(section.querySelector("h3").textContent).toBe("Lý do từ chối");
    expect(section.querySelector("lightning-formatted-text").value).toBe(
      element.request.rejectionReason
    );
    expect(section.querySelector("script")).toBeNull();
  });

  it("shows an authorized guest reason without exposing money", () => {
    const element = createElement("c-return-request-summary", {
      is: ReturnRequestSummary
    });
    element.request = {
      status: "REJECTED",
      rejectionReason: "Customer reason"
    };
    document.body.appendChild(element);
    expect(
      element.shadowRoot.querySelector("lightning-formatted-text").value
    ).toBe("Customer reason");
    expect(
      element.shadowRoot.querySelector('[data-section="amount"]')
    ).toBeNull();
  });

  it.each([
    ["NEW", "Stale reason"],
    ["REJECTED", null],
    ["REJECTED", "   "]
  ])(
    "hides an inapplicable or empty reason (%s, %s)",
    (status, rejectionReason) => {
      const element = createElement("c-return-request-summary", {
        is: ReturnRequestSummary
      });
      element.request = { status, rejectionReason };
      document.body.appendChild(element);
      expect(
        element.shadowRoot.querySelector('[data-section="rejection-reason"]')
      ).toBeNull();
    }
  );
});
