import { LightningElement } from "lwc";

export default class CustomerServiceFilters extends LightningElement {
  searchTerm = "";

  handleInputChange(event) {
    this.searchTerm = event.target.value;
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
          searchTerm: this.normalize(this.searchTerm)
        }
      })
    );
  }

  handleClear() {
    this.searchTerm = "";

    this.dispatchEvent(
      new CustomEvent("search", {
        detail: {
          searchTerm: null
        }
      })
    );
  }

  normalize(value) {
    const normalized = value?.trim();

    return normalized || null;
  }
}
