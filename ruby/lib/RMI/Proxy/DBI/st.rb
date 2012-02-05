package RMI::Proxy::DBI::st;

# install overrides to the default proxy options

$RMI::ProxyObject::DEFAULT_OPTS{"DBI::st"} = {
    fetchrow_hashref => {
        copy_results => 1,
    },
    #fetchrow_arrayref => {
    #   copy_results => 1,
    #},
    fetchall_arrayref => {
        copy_results => 1, 
    },
    
};        

