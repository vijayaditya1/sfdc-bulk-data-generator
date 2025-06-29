public with sharing class MockDataUtil {

    public static final String BASE_URL = URL.getOrgDomainUrl().toExternalForm();

    // Generate random field value based on field type
    public static String generateFieldValue(Schema.DescribeFieldResult field) {
        String fieldType = String.valueOf(field.getType());
        Integer length = field.getLength();
        String fieldName = field.getName();
        // Dynamically handle address fields with country/state picklist
        if (fieldName.endsWith('CountryCode')) {
            return 'US';
        } else if (fieldName.endsWith('StateCode')) {
            return 'CA';
        } else if (fieldName.endsWith('Country')) {
            return 'United States';
        } else if (fieldName.endsWith('State')) {
            return 'California';
        } else if (fieldName.endsWith('Longitude') || fieldName.endsWith('Latitude')) {
            return null;
        }
        switch on fieldType {
            when 'STRING', 'TEXTAREA' {
                return field.getLabel().removeEnd('Name') + generateRandomText(Math.min(length, 5));
            }
            when 'EMAIL' {
                return 'test' + generateRandomText(5) + '@test.com';
            }
            when 'PHONE' {
                return generateRandomPhone();
            }
            when 'PICKLIST' {
                List<Schema.PicklistEntry> entries = field.getPicklistValues();
                return entries.isEmpty() ? '' : entries[Math.mod(Math.abs(Crypto.getRandomInteger()), entries.size())].getValue();
            }
            when 'INTEGER', 'DOUBLE', 'CURRENCY', 'PERCENT' {
                return String.valueOf(Math.mod(Math.abs(Crypto.getRandomInteger()), 10000));
            }
            when 'DATE' {
                return Date.today().addDays(Math.mod(Math.abs(Crypto.getRandomInteger()), 365)).format();
            }
            when 'DATETIME' {
                return DateTime.now().addDays(Math.mod(Math.abs(Crypto.getRandomInteger()), 365)).format();
            }
            when else {
                return '';
            }
        }
    }

    // Generate random string of specified length
    private static String generateRandomText(Integer length) {
        String chars = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789';
        return generateRandomString(chars, length);
    }

    // Generate random phone number
    private static String generateRandomPhone() {
        String chars = '0123456789';
        return generateRandomString(chars, 10);
    }

    private static String generateRandomString(String chars, Integer length) {
        String result = '';
        for (Integer i = 0; i < length; i++) {
            Integer idx = Math.mod(Math.abs(Crypto.getRandomInteger()), chars.length());
            result += chars.substring(idx, idx + 1);
        }
        return result;
    }

    public static AuraHandledException getException(String message) {
        AuraHandledException ahe = new AuraHandledException(message);
        ahe.setMessage(message);
        return ahe;
    }

    
    // Class to hold field metadata and generation logic
    public class FieldConfig {
        @AuraEnabled public String label;
        @AuraEnabled public String value;
        
        public FieldConfig(String label, String value) {
            this.label = label;
            this.value = value;
        }
    }

    private static Map<SObjectType, DescribeSObjectResult> RESULT_CACHE = new Map<SObjectType, DescribeSObjectResult>();
    private static Map<SObjectType, DescribeSObjectResult> FIELD_RESULT_CACHE = new Map<SObjectType, DescribeSObjectResult>();

    public static DescribeSObjectResult getDescribe(SObjectType objectToken) {
        if (RESULT_CACHE.get(objectToken) == null) {
            RESULT_CACHE.put(objectToken, objectToken.getDescribe());
        }
        return RESULT_CACHE.get(objectToken);
    }

    public static DescribeFieldResult getFieldDescribe(SObjectType objectToken, String fieldName) {
        if (FIELD_RESULT_CACHE.get(objectToken) == null) {
            FIELD_RESULT_CACHE.put(objectToken, objectToken.getDescribe());
        }
        return FIELD_RESULT_CACHE.get(objectToken).fields.getMap().get(fieldName).getDescribe();
    }
}