constants = import_module("../package_io/constants.star")
input_parser = import_module("../package_io/input_parser.star")
node_metrics = import_module("../node_metrics_info.star")
remote_signer_context = import_module("./remote_signer_context.star")
shared_utils = import_module("../shared_utils/shared_utils.star")

REMOTE_SIGNER_KEYS_MOUNTPOINT = "/keystores"

REMOTE_SIGNER_CLIENT_NAME = "web3signer"

REMOTE_SIGNER_HTTP_PORT_NUM = 9000
REMOTE_SIGNER_HTTP_PORT_ID = "http"
REMOTE_SIGNER_METRICS_PORT_NUM = 9001
REMOTE_SIGNER_METRICS_PORT_ID = "metrics"

METRICS_PATH = "/metrics"

PRIVATE_IP_ADDRESS_PLACEHOLDER = "KURTOSIS_IP_ADDR_PLACEHOLDER"


REMOTE_SIGNER_USED_PORTS = {
    REMOTE_SIGNER_HTTP_PORT_ID: shared_utils.new_port_spec(
        REMOTE_SIGNER_HTTP_PORT_NUM,
        shared_utils.TCP_PROTOCOL,
        shared_utils.HTTP_APPLICATION_PROTOCOL,
    ),
    REMOTE_SIGNER_METRICS_PORT_ID: shared_utils.new_port_spec(
        REMOTE_SIGNER_METRICS_PORT_NUM,
        shared_utils.TCP_PROTOCOL,
        shared_utils.HTTP_APPLICATION_PROTOCOL,
    ),
}

# The min/max CPU/memory that the remote signer can use
MIN_CPU = 50
MAX_CPU = 300
MIN_MEMORY = 128
MAX_MEMORY = 1024


def launch(
    plan,
    launcher,
    service_name,
    image,
    node_keystore_files,
    remote_signer_min_cpu,
    remote_signer_max_cpu,
    remote_signer_min_mem,
    remote_signer_max_mem,
    extra_params,
    extra_labels,
    remote_signer_tolerations,
    participant_tolerations,
    global_tolerations,
    node_selectors,
):
    remote_signer_min_cpu = (
        int(remote_signer_min_cpu) if int(remote_signer_min_cpu) > 0 else MIN_CPU
    )
    remote_signer_max_cpu = (
        int(remote_signer_max_cpu) if int(remote_signer_max_cpu) > 0 else MAX_CPU
    )
    remote_signer_min_mem = (
        int(remote_signer_min_mem) if int(remote_signer_min_mem) > 0 else MIN_MEMORY
    )
    remote_signer_max_mem = (
        int(remote_signer_max_mem) if int(remote_signer_max_mem) > 0 else MAX_MEMORY
    )

    tolerations = input_parser.get_client_tolerations(
        remote_signer_tolerations, participant_tolerations, global_tolerations
    )

    config = get_config(
        el_cl_genesis_data=launcher.el_cl_genesis_data,
        image=image,
        node_keystore_files=node_keystore_files,
        remote_signer_min_cpu=remote_signer_min_cpu,
        remote_signer_max_cpu=remote_signer_max_cpu,
        remote_signer_min_mem=remote_signer_min_mem,
        remote_signer_max_mem=remote_signer_max_mem,
        extra_params=extra_params,
        extra_labels=extra_labels,
        tolerations=tolerations,
        node_selectors=node_selectors,
    )

    remote_signer_service = plan.add_service(service_name, config)

    remote_signer_http_port = remote_signer_service.ports[REMOTE_SIGNER_HTTP_PORT_ID]
    remote_signer_http_url = "http://{0}:{1}".format(
        remote_signer_service.ip_address, remote_signer_http_port.number
    )

    remote_signer_metrics_port = remote_signer_service.ports[
        REMOTE_SIGNER_METRICS_PORT_ID
    ]
    validator_metrics_url = "{0}:{1}".format(
        remote_signer_service.ip_address, remote_signer_metrics_port.number
    )
    remote_signer_node_metrics_info = node_metrics.new_node_metrics_info(
        service_name, METRICS_PATH, validator_metrics_url
    )

    return remote_signer_context.new_remote_signer_context(
        remote_signer_http_url=remote_signer_http_url,
        service_name=service_name,
        metrics_info=remote_signer_node_metrics_info,
    )


def get_config(
    el_cl_genesis_data,
    image,
    node_keystore_files,
    remote_signer_min_cpu,
    remote_signer_max_cpu,
    remote_signer_min_mem,
    remote_signer_max_mem,
    extra_params,
    extra_labels,
    tolerations,
    node_selectors,
):
    remote_signer_keys_dirpath = ""
    if node_keystore_files != None:
        remote_signer_keys_dirpath = shared_utils.path_join(
            REMOTE_SIGNER_KEYS_MOUNTPOINT,
            node_keystore_files.teku_keys_relative_dirpath,
        )
        remote_signer_secrets_dirpath = shared_utils.path_join(
            REMOTE_SIGNER_KEYS_MOUNTPOINT,
            node_keystore_files.teku_secrets_relative_dirpath,
        )

    cmd = [
        "--http-listen-port={0}".format(REMOTE_SIGNER_HTTP_PORT_NUM),
        "--http-host-allowlist=*",
        "--metrics-enabled=true",
        "--metrics-host-allowlist=*",
        "--metrics-host=0.0.0.0",
        "--metrics-port={0}".format(REMOTE_SIGNER_METRICS_PORT_NUM),
        "eth2",
        "--network="
        + constants.GENESIS_CONFIG_MOUNT_PATH_ON_CONTAINER
        + "/config.yaml",
        "--keystores-path=" + remote_signer_keys_dirpath,
        "--keystores-passwords-path=" + remote_signer_secrets_dirpath,
        # slashing protection would require postgres, migrations ... skipping for now
        "--slashing-protection-enabled=false",
    ]

    if len(extra_params) > 0:
        # this is a repeated<proto type>, we convert it into Starlark
        cmd.extend([param for param in extra_params])

    files = {
        constants.GENESIS_DATA_MOUNTPOINT_ON_CLIENTS: el_cl_genesis_data.files_artifact_uuid,
        REMOTE_SIGNER_KEYS_MOUNTPOINT: node_keystore_files.files_artifact_uuid,
    }

    return ServiceConfig(
        image=image,
        ports=REMOTE_SIGNER_USED_PORTS,
        cmd=cmd,
        files=files,
        private_ip_address_placeholder=PRIVATE_IP_ADDRESS_PLACEHOLDER,
        min_cpu=remote_signer_min_cpu,
        max_cpu=remote_signer_max_cpu,
        min_memory=remote_signer_min_mem,
        max_memory=remote_signer_max_mem,
        labels=shared_utils.label_maker(
            REMOTE_SIGNER_CLIENT_NAME,
            constants.CLIENT_TYPES.remote_signer,
            image,
            "",
            extra_labels,
        ),
        tolerations=tolerations,
        node_selectors=node_selectors,
    )


def new_remote_signer_launcher(el_cl_genesis_data):
    return struct(el_cl_genesis_data=el_cl_genesis_data)
