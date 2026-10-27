import { LightningElement } from "lwc";
import { NavigationMixin } from "lightning/navigation";
import isGuest from "@salesforce/user/isGuest";
import basePath from "@salesforce/community/basePath";

export default class PortalNavigation extends NavigationMixin(
  LightningElement
) {
  isGuest = isGuest;

  get logoutUrl() {
    return `${basePath.replace(/\/s\/?$/, "").replace(/\/$/, "")}/secur/logout.jsp`;
  }

  handleNavigate(event) {
    this[NavigationMixin.Navigate]({
      type: "comm__namedPage",
      attributes: { name: event.currentTarget.dataset.page }
    });
  }
}
