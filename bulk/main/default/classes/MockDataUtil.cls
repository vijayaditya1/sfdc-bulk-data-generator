public with sharing class MockDataUtil {

    public static final String BASE_URL = URL.getOrgDomainUrl().toExternalForm();

    // Generate random field value based on field type
    public static String generateFieldValue(SObject record, Schema.DescribeFieldResult field) {
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
                String text = field.getLabel().removeEnd('Name') + generateRandomText(Math.min(length, 5));
                return text.right(field.getLength()).trim();
            }
            when 'EMAIL' {
                return 'test' + generateRandomText(5) + '@test.com';
            }
            when 'PHONE' {
                return generateRandomPhone();
            }
            when 'PICKLIST', 'MULTIPICKLIST' {
                if (field.isDependentPicklist()) {
                    Schema.SObjectField controller = field.getController();
                    String controllerValueStored = String.valueOf(record.get(controller.getDescribe().getName()));
                    if (String.isNotBlank(controllerValueStored)) {
                        return getDependentPicklistValues(field).get(controllerValueStored)[0];
                    }
                    List<Schema.PicklistEntry> entries = controller.getDescribe().getPicklistValues();
                    String controllerValue = entries.isEmpty() ? '' : entries[Math.mod(Math.abs(Crypto.getRandomInteger()), entries.size())].getValue();
                    record.put(controller.getDescribe().getName(), controllerValue);
                    return getDependentPicklistValues(field).get(controllerValue)[0];
                } else {
                    if (String.isBlank(String.valueOf(record.get(field.getName())))) {
                        List<Schema.PicklistEntry> entries = field.getPicklistValues();
                        return entries.isEmpty() ? '' : entries[Math.mod(Math.abs(Crypto.getRandomInteger()), entries.size())].getValue();
                    }
                    return String.valueOf(record.get(field.getName()));
                }
            }
            when 'INTEGER', 'DOUBLE', 'CURRENCY' {
                String textNumber = String.valueOf(Math.mod(Math.abs(Crypto.getRandomInteger()), 10000));
                return textNumber.left(field.getPrecision() - field.getScale()).trim();
            }
            when 'PERCENT' {
                return String.valueOf(Math.mod(Math.abs(Crypto.getRandomInteger()), 100));
            }
            when 'DATE' {
                return DateTime.now().addDays(Math.mod(Math.abs(Crypto.getRandomInteger()), 365)).format('yyyy-MM-dd');
            }
            when 'DATETIME' {
                return DateTime.now().addDays(Math.mod(Math.abs(Crypto.getRandomInteger()), 365)).format('yyyy-MM-ddTHH:mm:ss.SSSZ');
            }
            when 'TIME' {
                Integer num = Math.abs(Crypto.getRandomInteger());
                return (Math.mod(num, 24) + ':').leftPad(3, '0') + (Math.mod(num, 60) + ':').leftPad(3, '0') + (Math.mod(num, 24) + '').leftPad(2, '0');
            }
            when 'URL' {
                return 'www.' + generateRandomText(Math.min(length, 9)).toLowerCase() + '.com';
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

    public static Map<String, List<String>> getDependentPicklistValues(Schema.DescribeFieldResult dependentFieldResult) {
        Map<String, List<String>> dependentPicklistValues = new Map<String, List<String>>();
        Schema.sObjectField controllerField = dependentFieldResult.getController();
        if (controllerField == null) {
            return null;
        }

        String BASE_DATA_MAP = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
        Schema.DescribeFieldResult controllerFieldResult = controllerField.getDescribe();
        List<Schema.PicklistEntry> controllerValues = (controllerFieldResult.getType() == Schema.DisplayType.Boolean ? null : controllerFieldResult.getPicklistValues());
        String base64map = BASE_DATA_MAP;
        
        for(Schema.PicklistEntry entry : dependentFieldResult.getPicklistValues()){
            if (entry.isActive()) {
                map<String,Object> mapEntry = (Map<String, Object>)JSON.deserializeUntyped(JSON.serialize(entry));
                if(mapEntry != null && mapEntry.containsKey('validFor') && mapEntry.get('validFor') != null &&
                    ((String)(mapEntry.get('validFor'))) != '' ){
                    List<String> base64chars = String.valueOf(((Map<String, Object>)JSON.deserializeUntyped(JSON.serialize(entry))).get('validFor')).split('');
                    if(base64chars != null && !base64chars.isEmpty()){
                        for (Integer i = 0; i < controllerValues.size(); i++){
                            Object controllerValue = (controllerValues == null ? (Object) (i == 1) : (Object) (controllerValues[i].isActive() ? controllerValues[i].getLabel() : null));
                            Integer bitIndex = i/6;
                            Integer bitShift = 5 - Math.mod(i, 6);
                            if(controllerValue == null || (base64map.indexOf(base64chars[bitIndex]) & (1 << bitShift)) == 0){
                                continue;
                            }
                            String controllerValueStr = String.valueOf(controllerValue);
                            if (dependentPicklistValues.containsKey(controllerValueStr)) {
                                dependentPicklistValues.get(controllerValueStr).add(entry.getValue());
                            } else {
                                dependentPicklistValues.put(controllerValueStr, new List<String>{entry.getValue()});
                            }
                        }
                    }
                }
            }
        }
        return dependentPicklistValues;
    }
}