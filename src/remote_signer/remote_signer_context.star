def new_remote_signer_context(
    remote_signer_http_url,
    service_name,
    metrics_info,
):
    return struct(
        remote_signer_http_url=remote_signer_http_url,
        service_name=service_name,
        metrics_info=metrics_info,
    )
