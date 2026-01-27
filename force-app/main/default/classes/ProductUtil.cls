public class ProductUtil {
    private static Map<String, Id> productCache = new Map<String, Id>();

    public static Id getProductId(String productName) {
        if (!productCache.containsKey(productName)) {
            productCache.put(productName, [SELECT Id FROM Product2 WHERE Name = :productName LIMIT 1].Id);
        }
        return productCache.get(productName);
    }
}