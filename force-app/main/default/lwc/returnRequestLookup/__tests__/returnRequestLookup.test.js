import { createElement } from "lwc";
import ReturnRequestLookup from "c/returnRequestLookup";

const flush = async () => {
  await Promise.resolve();
  await Promise.resolve();
};

function render() {
  const element = createElement("c-return-request-lookup", {
    is: ReturnRequestLookup
  });
  element.showProducts = true;
  element.guestSitePath = "/smartreturnvforcesite";
  document.body.appendChild(element);
  return element;
}

function fill(element, code = "RR-2610-00001", suffix = "4567") {
  const input = element.shadowRoot.querySelector("lightning-input");
  input.checkValidity = jest.fn(() => true);
  input.reportValidity = jest.fn(() => true);
  input.setCustomValidity = jest.fn();
  input.value = `${code} ${suffix}`;
  input.dispatchEvent(new CustomEvent("change"));
}

function submit(element) {
  element.shadowRoot
    .querySelector("form")
    .dispatchEvent(new CustomEvent("submit", { cancelable: true }));
}

describe("guest return lookup", () => {
  beforeEach(() => {
    global.fetch = jest.fn();
  });
  afterEach(() => {
    document.body.replaceChildren();
    jest.clearAllMocks();
  });

  it("sends proof in the POST body and renders the restricted result", async () => {
    global.fetch.mockResolvedValue({
      ok: true,
      json: async () => ({
        outcome: "FOUND",
        request: {
          requestNumber: "RR-2610-00001",
          status: "REFUND_FAILED",
          lines: [{ productName: "Nồi chiên", quantity: 1 }],
          history: []
        }
      })
    });
    const element = render();
    fill(element);
    submit(element);
    await flush();
    expect(global.fetch).toHaveBeenCalledTimes(1);
    const [url, options] = global.fetch.mock.calls[0];
    expect(url).toBe(
      "/smartreturnvforcesite/services/apexrest/smartreturn/v1/portal/lookup"
    );
    expect(url).not.toContain("4567");
    expect(JSON.parse(options.body)).toEqual({
      requestNumber: "RR-2610-00001",
      phoneSuffix: "4567"
    });
    const result = element.shadowRoot.querySelector("c-return-request-summary");
    expect(result).not.toBeNull();
    expect(result.showAmount).toBe(false);
    expect(element.shadowRoot.querySelector("lightning-input").value).toBe("");
  });

  it("renders one input with Builder-configurable title and description", async () => {
    const element = render();
    element.heading = "Tra cứu mã của bạn";
    element.subtitle = "Nhập mã và 4 số cuối, cách nhau bằng dấu cách.";
    await flush();
    expect(element.shadowRoot.querySelectorAll("lightning-input")).toHaveLength(
      1
    );
    expect(element.shadowRoot.querySelector("h1").textContent).toBe(
      element.heading
    );
    expect(element.shadowRoot.querySelector(".intro").textContent).toBe(
      element.subtitle
    );
    expect(element.shadowRoot.querySelector("lightning-input").label).toBe(
      element.heading
    );
  });

  it.each(["RR-2610-00001", "RR-2610-00001 123", "RR-2610-00001 12345"])(
    "rejects malformed combined proof locally: %s",
    async (value) => {
      const element = render();
      fill(element, value, "");
      submit(element);
      await flush();
      expect(global.fetch).not.toHaveBeenCalled();
      expect(
        element.shadowRoot.querySelector("lightning-input").setCustomValidity
      ).toHaveBeenLastCalledWith(expect.stringContaining("4 số cuối"));
    }
  );

  it("trims pasted whitespace and preserves leading zeroes in the phone suffix", async () => {
    global.fetch.mockResolvedValue({
      ok: true,
      json: async () => ({ outcome: "NOT_FOUND" })
    });
    const element = render();
    fill(element, "  RR-2610-00001  ", "0012  ");
    submit(element);
    await flush();
    expect(JSON.parse(global.fetch.mock.calls[0][1].body)).toEqual({
      requestNumber: "RR-2610-00001",
      phoneSuffix: "0012"
    });
  });

  it("clears a previous result before showing the uniform no-match error", async () => {
    global.fetch.mockResolvedValueOnce({
      ok: true,
      json: async () => ({
        outcome: "FOUND",
        request: {
          requestNumber: "RR-2610-00001",
          status: "NEW",
          lines: [],
          history: []
        }
      })
    });
    const element = render();
    fill(element);
    submit(element);
    await flush();
    global.fetch.mockResolvedValueOnce({
      ok: true,
      json: async () => ({ outcome: "NOT_FOUND" })
    });
    fill(element, "RR-UNKNOWN", "0000");
    submit(element);
    await flush();
    expect(
      element.shadowRoot.querySelector("c-return-request-summary")
    ).toBeNull();
    expect(
      element.shadowRoot.querySelector('[role="alert"]').textContent
    ).toContain("Không tìm thấy yêu cầu phù hợp");
  });

  it("shows the lock state without revealing a customer record", async () => {
    global.fetch.mockResolvedValue({
      ok: true,
      json: async () => ({ outcome: "LOCKED", retryAfterMinutes: 15 })
    });
    const element = render();
    fill(element);
    submit(element);
    await flush();
    expect(
      element.shadowRoot.querySelector('[role="alert"]').textContent
    ).toContain("15 phút");
    expect(
      element.shadowRoot.querySelector("c-return-request-summary")
    ).toBeNull();
  });

  it("never posts phone proof to an external configured URL", async () => {
    const element = render();
    element.guestSitePath = "https://external.example/lookup";
    fill(element);
    submit(element);
    await flush();
    expect(global.fetch).not.toHaveBeenCalled();
    expect(
      element.shadowRoot.querySelector('[role="alert"]').textContent
    ).toContain("Không thể tra cứu");
  });

  it("rejects duplicate submissions while one lookup is pending", async () => {
    let complete;
    global.fetch.mockReturnValue(
      new Promise((resolve) => {
        complete = resolve;
      })
    );
    const element = render();
    fill(element);
    submit(element);
    submit(element);
    expect(global.fetch).toHaveBeenCalledTimes(1);
    complete({ ok: false });
    await flush();
    expect(
      element.shadowRoot.querySelector('[role="alert"]').textContent
    ).toContain("Không thể tra cứu");
    expect(element.shadowRoot.querySelector("lightning-button").disabled).toBe(
      false
    );
  });
});
