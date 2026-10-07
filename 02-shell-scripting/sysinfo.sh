#!/bin/bash
#===============================================================
# sysinfo.sh - System Information Script
# Author      : THRISHAL DOMA
# Enrollment  : 24BCS10097
# Description : Collects system information, takes user input,
#               creates a directory and file, and stores running
#               process data using output redirection.
#===============================================================

# ---------- 1. VARIABLES via command substitution ----------
current_date=$(date '+%A, %d %B %Y - %H:%M:%S')
host_name=$(hostname)
user_name=$(whoami)
kernel_version=$(uname -r)

# ---------- 2. USER INPUT with read -p ----------
echo "=============================================="
echo "        SYSTEM INFORMATION SCRIPT"
echo "=============================================="
echo ""
read -p "Enter your name          : " student_name
read -p "Enter your enrollment no : " enrollment_no
read -p "Enter a report folder name [default: system-report]: " report_dir
report_dir=${report_dir:-system-report}
echo ""

# ---------- 3. SYSTEM INFORMATION ----------
echo "----------------------------------------------"
echo " SUBMITTED BY"
echo "----------------------------------------------"
echo "Name          : $student_name"
echo "Enrollment No : $enrollment_no"
echo ""
echo "----------------------------------------------"
echo " SYSTEM DETAILS"
echo "----------------------------------------------"
echo "Current Date  : $current_date"
echo "Hostname      : $host_name"
echo "Username      : $user_name"
echo "Kernel        : $kernel_version"
echo ""

# ---------- 4. DISK USAGE ----------
echo "----------------------------------------------"
echo " DISK USAGE (df -h)"
echo "----------------------------------------------"
df -h
echo ""

# ---------- 5. RUNNING PROCESSES ----------
echo "----------------------------------------------"
echo " RUNNING PROCESSES (first 10)"
echo "----------------------------------------------"
ps aux | head -11
echo ""

# ---------- 6. CREATE DIRECTORY (mkdir) AND FILE (touch) ----------
mkdir -p "$report_dir"
echo "[+] Directory created : $report_dir"
process_file="$report_dir/process.log"
disk_file="$report_dir/disk-usage.log"
touch "$process_file"
echo "[+] File created      : $process_file"
echo ""

# ---------- 7. OUTPUT REDIRECTION ( > overwrite, >> append ) ----------
echo "===== PROCESS REPORT =====" >  "$process_file"
echo "Generated : $current_date" >> "$process_file"
echo "Host      : $host_name"    >> "$process_file"
echo "User      : $user_name"    >> "$process_file"
echo "Student   : $student_name ($enrollment_no)" >> "$process_file"
echo "" >> "$process_file"
ps aux >> "$process_file"

df -h > "$disk_file"

echo "[+] Running processes saved to  : $process_file"
echo "[+] Disk usage saved to         : $disk_file"
echo "[+] Lines written to process.log: $(wc -l < "$process_file")"
echo ""
echo "=============================================="
echo " Script completed successfully."
echo "=============================================="
