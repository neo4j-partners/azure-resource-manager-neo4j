# azure-resource-manager-neo4j
These are Azure Resource Manager (ARM) templates that deploy Neo4j Enterprise on Azure.  They set up Neo4j Graph Database, Graph Data Science and Bloom.  

* [simple](simple) is probably the best place to start.  
* [marketplace](marketplace) is the template used in the Neo4j Azure Marketplace listing.  It has some Marketplace specific variables in it.  If deploying outside the marketplace, you probably want to use [simple](simple) instead.
* [extensions](extensions) contains extensions shared by all the ARM templates.