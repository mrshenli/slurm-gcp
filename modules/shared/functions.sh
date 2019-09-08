################
# Create the slurm group and user with gid, uid set to 992
# Globals:
#  None
# Arguments:
#  None
# Returns:
#  None
################
function add_slurm_user {
    groupadd -g 992 slurm
    useradd -m -c "SLURM Workload Manager" -d /var/lib/slurm -u 992 -g slurm -s /bin/bash slurm
}

################
# Create the systemd munge.service unit file and generate a munge key
# Globals:
#  None
# Arguments:
#  None
# Returns:
#  None
################
function setup_munge {
    cat << MUNGE > /usr/lib/systemd/system/munge.service
[Unit]
Description=MUNGE authentication service
Documentation=man:munged(8)
After=network.target
After=syslog.target
After=time-sync.target
RequiresMountsFor=/etc/munge
    
[Service]
Type=forking
ExecStart=/usr/sbin/munged --num-threads=10
PIDFile=/var/run/munge/munged.pid
User=munge
Group=munge
Restart=on-abort

[Install]
WantedBy=multi-user.target
MUNGE

    create-munge-key
}

################
# Start the systemd munge.service
# Globals:
#  None
# Arguments:
#  None
# Returns:
#  None
################
function start_munge {
    systemctl start munge.service
}

################
# Add the current slurm installation's bin/ and sbin/ directories to PATH
# Globals:
#  PATH
# Arguments:
#  current_slurmdir - [optional, defaults to /apps/slurm/current] root of current slurm installation
# Returns:
#  None
################
function setup_bash_profile { 
    current_slurmdir="${1:-/apps/slurm/current}"

    cat <<PROFILE > /etc/profile.d/slurm.sh
PATH="$PATH:${current_slurmdir}/bin:${current_slurmdir}/sbin"
PROFILE
}

################
# Add /etc/fstab entries for NFS volumes
# Globals:
#  None
# Arguments:
#  server - name or IP address of the NFS volume host
#  directories - list of directories to be mounted from server
# Returns:
#  None
################
function setup_nfs_vols {
    local server=$1
    shift
    for dir in $@
    do
        echo -e "$server:$dir\t$dir\tnfs\trw,hard,intr\t0\t0" | cat - >> /etc/fstab
    done
}

################
# Add /etc/exports entries for NFS volumes
# Globals:
#  None
# Arguments:
#  directories - list of directories being exported
# Returns:
#  None
################
function setup_nfs_exports {
    for dir in  $@
    do
        echo -e "$dir\t*(rw,no_subtree_check,no_root_squash)" | cat - >> /etc/exports
    done

    exportfs -a
}

################
# Increase the number of threads created by the NFS daemon
# TODO:
#  /etc/sysconfig/nfs is deprecated as of RHEL 7 should use /etc/nfs.conf instead
# Globals:
#  None
# Arguments:
#  None
# Returns:
#  None
################
function setup_nfs_threads {
    cat <<NFSTHREADS >> /etc/sysconfig/nfs
RPCNFSDCOUNT=256
NFSTHREADS
}

################
# Mount NFS volumes
# Globals:
#  None
# Arguments:
#  None
# Returns:
#  None
################
function mount_nfs_vols {
    mount -a
}

################
# Download and install a specified version of Slurm
# Globals:
#  None
# Arguments:
#  version - version of Slurm to download and install
#  appsdir - [optional, defaults to /apps] target install directory
# Returns:
#  None
################
function install_slurm {
    local appsdir="${2:-/apps}"
    local homedir="/home"

    local which_slurm="slurm-$1"

    local slurm_archive="${which_slurm}.tar.bz2"
    local slurm_rootdir="${appsdir}/slurm"
    local slurm_srcdir="${slurm_rootdir}/src"
    local slurm_current="${slurm_rootdir}/current"
    
    cd ${slurm_srcdir}

    wget https://download.schedmd.com/slurm/${slurm_archive}
    tar -xvjf ${slurm_archive}
    rm ${slurm_archive}

    [ ! -d ${slurm_current} ] && mkdir -p ${slurm_current}/etc
    cd $slurm_srcdir/${which_slurm}

    [ ! -d "build" ] && mkdir build
    cd build

    ../configure --prefix=${SLURM_SRCDIR}/${WHICH_SLURM} --sysconfdir=${SLURM_CURRENT}/etc
    make -j install
}

################
# Add slurm.conf to /etc/tmpfiles.d
# Globals:
#  None
# Arguments:
#  rundir - [optional, defaults to /var/run/slurm] runtime data directory for Slurm
# Returns:
#  None
################
function setup_slurm_tmpfile {
    local rundir=${1:-/var/run/slurm}

    cat <<SLURMCONF > /etc/tmpfiles.d/slurm.conf
d ${rundir} 0755 slurm slurm -
SLURMCONF

    [[ ! -d ${rundir} ]] && mkdir ${rundir}
    chmod 755 ${rundir}
    chown slurm: ${rundir}
}

################
# Create systemd service unit files for the Slurm daemons
# Globals:
#  None
# Arguments:
#  current_slurmdir - [optional, defaults to /apps/slurm/current] root of current slurm installation
# Returns:
#  None
################
function setup_slurm_units {
    current_slurmdir="${1:-/apps/slurm/current}"

    cat <<SLURMCTLD > /usr/lib/systemd/system/slurmctld.service
[Unit]
Description=Slurm controller daemon
After=network.target munge.service
ConditionPathExists=${current_slurmdir}/etc/slurm.conf

[Service]
Type=forking
EnvironmentFile=-/etc/sysconfig/slurmctld
ExecStart=${current_slurmdir}/sbin/slurmctld $SLURMCTLD_OPTIONS
ExecReload=/bin/kill -HUP $MAINPID
PIDFile=/var/run/slurm/slurmctld.pid

[Install]
WantedBy=multi-user.target
SLURMCTLD

    cat <<SLURMDBD > /usr/lib/systemd/system/slurmdbd.service
[Unit]
Description=Slurm DBD accounting daemon
After=network.target munge.service
ConditionPathExists=${current_slurmdir}/etc/slurmdbd.conf

[Service]
Type=forking
EnvironmentFile=-/etc/sysconfig/slurmdbd
ExecStart=${current_slurmdir}/sbin/slurmdbd $SLURMDBD_OPTIONS
ExecReload=/bin/kill -HUP $MAINPID
PIDFile=/var/run/slurm/slurmdbd.pid

[Install]
WantedBy=multi-user.target
SLURMDBD
}
