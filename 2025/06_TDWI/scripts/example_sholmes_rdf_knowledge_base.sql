BEGIN
  SEM_APIS.DROP_SEM_NETWORK (
    cascade => true
    -- TRUE drops any existing semantic technology models and rulebases, and removes structures
    -- used for persistent storage of semantic data; FALSE (the default) causes the operation to fail
    -- if any semantic technology models or rulebases exist.
    , network_owner => 'TDWIUSER'
    , network_name => 'RDF_NETWORK'
  );
END;
/

BEGIN
  SEM_APIS.CREATE_SEM_NETWORK (
    tablespace_name => 'DATA'
    , network_owner => 'TDWIUSER'
    , network_name => 'RDF_NETWORK'
  );
END;
/

DROP TABLE IF EXISTS sholmes_rdf_kb PURGE;
CREATE TABLE IF NOT EXISTS sholmes_rdf_kb (triple SDO_RDF_TRIPLE_S) COMPRESS;

BEGIN
  SEM_APIS.DROP_SEM_MODEL (
    model_name => 'SHOLMES'
    , network_owner => 'TDWIUSER'
    , network_name => 'RDF_NETWORK'
  );
END;
/

BEGIN
  SEM_APIS.CREATE_SEM_MODEL(
    model_name => 'SHOLMES'
    , table_name => 'SHOLMES_RDF_KB'
    , column_name => 'TRIPLE'
    , network_owner => 'TDWIUSER'
    , network_name => 'RDF_NETWORK'
  );
END;
/

-- Load RDF triples using SEM_APIS.UPDATE_MODEL
BEGIN
  -- Insert some TBox (schema) information.
  SEM_APIS.UPDATE_MODEL (
    'sholmes' ,
    'PREFIX     rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
    PREFIX    rdfs: <http://www.w3.org/2000/01/rdf-schema#>
    PREFIX sholmes: <http://www.example.org/sholmes/>
    INSERT DATA {
      # Person is a class
      sholmes:Person rdf:type rdfs:Class .

      # Male is a subclass of Person
      sholmes:Male rdfs:subClassOf family:Person .

      # Female is a subclass of Person
      sholmes:Female rdfs:subClassOf family:Person .

      # siblingOf is a property
      sholmes:siblingOf rdf:type rdf:Property .

      # parentOf is a property
      sholmes:parentOf rdf:type rdf:Property .

      # brotherOf is a subproperty of siblingOf
      sholmes:brotherOf rdfs:subPropertyOf family:siblingOf .

      # sisterOf is a subproperty of siblingOf
      sholmes:sisterOf rdfs:subPropertyOf family:siblingOf .

      # A brother is male
      sholmes:brotherOf rdfs:domain family:Male .

      # A sister is female
      sholmes:sisterOf rdfs:domain family:Female .

      # fatherOf is a subproperty of parentOf
      sholmes:fatherOf rdfs:subPropertyOf family:parentOf .

      # motherOf is a subproperty of parentOf
      sholmes:motherOf rdfs:subPropertyOf family:parentOf .

      # A father is male
      sholmes:fatherOf rdfs:domain family:Male .

      # A mother is female
      sholmes:motherOf rdfs:domain family:Female .
      }'
  , network_owner=>'TDWIUSER'
  , network_name=>'RDF_NETWORK'
  );

    -- Insert some ABox (instance) information.
    SEM_APIS.UPDATE_MODEL (
        'sholmes'
        , 'PREFIX     rdf: <http://www.w3.org/1999/02/22-rdf-syntax-ns#>
           PREFIX    rdfs: <http://www.w3.org/2000/01/rdf-schema#>
           PREFIX sholmes: <http://www.example.org/family/>
           INSERT DATA {
                # John is the father of Suzie and Matt
                family:John family:fatherOf family:Suzie .
                family:John family:fatherOf family:Matt .

                # Janice is the mother of Suzie and Matt
                family:Janice family:motherOf family:Suzie .
                family:Janice family:motherOf family:Matt .

                # Sammy is the father of Cathy and Jack
                family:Sammy family:fatherOf family:Cathy .
                family:Sammy family:fatherOf family:Jack .

                # Suzie is the mother of Cathy and Jack
                family:Suzie family:motherOf family:Cathy .
                family:Suzie family:motherOf family:Jack .

                # Matt is the father of Tom and Cindy
                family:Matt family:fatherOf family:Tom .
                family:Matt family:fatherOf family:Cindy .

                # Martha is the mother of Tom and Cindy
                family:Martha family:motherOf family:Tom .
                family:Martha family:motherOf family:Cindy .

                # Cathy is the sister of Jack
                family:Cathy family:sisterOf family:Jack .

                # Jack is male
                family:Jack rdf:type family:Male .

                # Tom is male
                family:Tom rdf:type family:Male .

                # Cindy is female
                family:Cindy rdf:type family:Female .
            }'
        , network_owner=>'RDFUSER'
        , network_name=>'RDF_NETWORK'
    );
END;
/