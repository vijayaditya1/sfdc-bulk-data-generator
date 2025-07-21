# bulk data generator

This small application can generate bulk records in the org. While generating the data it includes the selected fields, and any required fields as well. Relationship fields are also taken care of, as it check if there are any lookup / master-detail field, creates the sample records in parent object and add the ids to those fields.

<h2>Features / Considerations</h2>

- Tested till 4M records, probably can be increased in code
- Uses bulk api 2.0
- Handles heap size and cpu time limit
- Chunk size depends on the fields selected
- Creates parent records per 100K records (not good for skew, but just for testing purpose)
- Handles parent's required fields too, but doesn't handle parent's parent, and probably fail if marked required
- Owner / RecordTypeId are not handled
- Progress can be checked for Batch only right now, not for bulk query, need a custom setting creation to track that
