public inherited sharing class ReturnCategoryPolicySelector {
  public static Map<String, Return_Category_Policy__mdt> selectActivePoliciesByFamily() {
    Map<String, Return_Category_Policy__mdt> policiesByFamily = new Map<String, Return_Category_Policy__mdt>();

    for (
      Return_Category_Policy__mdt policy : Return_Category_Policy__mdt.getAll()
        .values()
    ) {
      if (
        policy.Is_Active__c == true &&
        String.isNotBlank(policy.Product_Family__c)
      ) {
        policiesByFamily.put(normalizeFamily(policy.Product_Family__c), policy);
      }
    }

    return policiesByFamily;
  }

  public static String normalizeFamily(String productFamily) {
    return String.isBlank(productFamily)
      ? null
      : productFamily.trim().toLowerCase();
  }
}
