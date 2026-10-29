import { LightningElement } from "lwc";

export default class CustomerServiceFilters extends LightningElement {
  customerPhone = "";
  orderNumber = "";
  customerName = "";

  handleInputChange(event) {
    const { name, value } = event.target;
    this[name] = value;
  }

  handleKeyUp(event) {
    if (event.key === "Enter") {
      this.handleSearch();
    }
  }

  handleSearch() {
    this.dispatchEvent(
      new CustomEvent("search", {
        detail: {
          customerPhone: this.normalize(this.customerPhone),
          orderNumber: this.normalize(this.orderNumber),
          customerName: this.normalize(this.customerName)
        }
      })
    );
  }

  handleClear() {
    this.customerPhone = "";
    this.orderNumber = "";
    this.customerName = "";

    this.dispatchEvent(
      new CustomEvent("search", {
        detail: {
          customerPhone: null,
          orderNumber: null,
          customerName: null
        }
      })
    );
  }

  normalize(value) {
    const normalized = value?.trim();
    return normalized || null;
  }
}
