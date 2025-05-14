#!/bin/bash

STUDENT_FILE="students.txt"
FACULTY_FILE="faculties.txt"
SUDO_LOG="sudo_commands.log"
CRED_FILE="credentials.txt"

touch "$STUDENT_FILE" "$FACULTY_FILE" "$SUDO_LOG" "$CRED_FILE"

ADMIN_USERNAME="admin"
ADMIN_PASSWORD="admin123"

# Initialize admin credentials if not present
if ! grep -q "^$ADMIN_USERNAME:admin:" "$CRED_FILE"; then
    hash=$(echo -n "$ADMIN_PASSWORD" | sha256sum | cut -d' ' -f1)
    echo "$ADMIN_USERNAME:admin:$hash" >> "$CRED_FILE"
fi

user_exists() { 
    id "$1" &>/dev/null
}

log_sudo_command() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') | $USER | $1" >> "$SUDO_LOG"
}

authenticate_user() {
    role="$1"
    username=$(dialog --stdout --inputbox "Enter your $role username:" 8 40)
    password=$(dialog --stdout --insecure --passwordbox "Enter password:" 8 40)

    hash=$(echo -n "$password" | sha256sum | cut -d' ' -f1)

    if grep -q "^$username:$role:$hash" "$CRED_FILE"; then
        echo "$username"
    else
        dialog --msgbox "Authentication failed!" 6 40
        echo ""
    fi
}

view_student_details() {
    student_id=$(dialog --stdout --inputbox "Enter your Student ID:" 8 40)
    if grep -q ":$student_id:" "$STUDENT_FILE"; then
        line=$(grep ":$student_id:" "$STUDENT_FILE")
        username=$(echo "$line" | cut -d':' -f1)
        group=$(echo "$line" | cut -d':' -f3)
        info="Username: $username\nStudent ID: $student_id\nGroup: $group"
        dialog --msgbox "$info" 10 50
    else
        dialog --msgbox "Student ID '$student_id' not found!" 6 50
    fi
}

add_student() {
    username=$(dialog --stdout --inputbox "Enter student username:" 8 40)
    student_id=$(dialog --stdout --inputbox "Enter unique student ID:" 8 40)
    group=$(dialog --stdout --inputbox "Enter group name:" 8 40)

    if grep -q "^$username:" "$STUDENT_FILE" || grep -q ":$student_id:" "$STUDENT_FILE"; then
        dialog --msgbox "Student with same username or ID already exists!" 6 50
    else
        echo "$username:$student_id:$group" >> "$STUDENT_FILE"
        dialog --msgbox "Student '$username' added." 6 40
    fi
}

remove_student() {
    student_id=$(dialog --stdout --inputbox "Enter student ID to remove:" 8 40)
    if grep -q ":$student_id:" "$STUDENT_FILE"; then
        sed -i "/:$student_id:/d" "$STUDENT_FILE"
        dialog --msgbox "Student ID '$student_id' removed." 6 50
    else
        dialog --msgbox "Student ID '$student_id' not found!" 6 50
    fi
}

add_faculty() {
    username=$(dialog --stdout --inputbox "Enter faculty username:" 8 40)
    group=$(dialog --stdout --inputbox "Enter group they lead:" 8 40)
    password=$(dialog --stdout --insecure --passwordbox "Set password for faculty:" 8 40)

    if grep -q "^$username:" "$FACULTY_FILE" || grep -q ":$group\$" "$FACULTY_FILE"; then
        dialog --msgbox "Faculty with same username or group already exists!" 6 50
    elif grep -q "^$username:faculty:" "$CRED_FILE"; then
        dialog --msgbox "This faculty already has credentials." 6 50
    else
        echo "$username:$group" >> "$FACULTY_FILE"
        hash=$(echo -n "$password" | sha256sum | cut -d' ' -f1)
        echo "$username:faculty:$hash" >> "$CRED_FILE"
        dialog --msgbox "Faculty '$username' added with credentials." 6 50
    fi
}

remove_faculty() {
    username=$(dialog --stdout --inputbox "Enter faculty username to remove:" 8 40)
    if grep -q "^$username:" "$FACULTY_FILE"; then
        sed -i "/^$username:/d" "$FACULTY_FILE"
        sed -i "/^$username:faculty:/d" "$CRED_FILE"
        dialog --msgbox "Faculty '$username' removed." 6 50
    else
        dialog --msgbox "Faculty not found!" 6 50
    fi
}

lock_student() {
    student_id=$(dialog --stdout --inputbox "Enter student ID to lock:" 8 40)
    username=$(grep ":$student_id:" "$STUDENT_FILE" | cut -d':' -f1)

    if [ -n "$username" ] && user_exists "$username"; then
        if sudo usermod -L "$username"; then
            log_sudo_command "Locked user $username"
            dialog --msgbox "Locked user '$username' (ID: $student_id)." 6 50
        else
            dialog --msgbox "Failed to lock user '$username'. Check permissions." 6 60
        fi
    else
        dialog --msgbox "Student ID or user not found in system!" 6 50
    fi
}

unlock_student() {
    student_id=$(dialog --stdout --inputbox "Enter student ID to unlock:" 8 40)
    username=$(grep ":$student_id:" "$STUDENT_FILE" | cut -d':' -f1)

    if [ -n "$username" ] && user_exists "$username"; then
        if sudo usermod -U "$username"; then
            log_sudo_command "Unlocked user $username"
            dialog --msgbox "Unlocked user '$username' (ID: $student_id)." 6 50
        else
            dialog --msgbox "Failed to unlock user '$username'. Check permissions." 6 60
        fi
    else
        dialog --msgbox "Student ID or user not found in system!" 6 50
    fi
}

set_expiry() {
    student_id=$(dialog --stdout --inputbox "Enter student ID to set expiry for:" 8 40)
    username=$(grep ":$student_id:" "$STUDENT_FILE" | cut -d':' -f1)

    if [ -n "$username" ] && user_exists "$username"; then
        expiry_date=$(dialog --stdout --inputbox "Enter expiry date (YYYY-MM-DD):" 8 40)
        sudo chage -E "$expiry_date" "$username"
        log_sudo_command "Set expiry for $username to $expiry_date"
        dialog --msgbox "Set expiry for '$username' to $expiry_date." 6 50
    else
        dialog --msgbox "Student ID or user not found!" 6 50
    fi
}

show_students() {
    {
        echo "USERNAME    | ID    | GROUP"
        echo "----------------------------"
        column -t -s ':' "$STUDENT_FILE"
    } > temp_students.txt
    dialog --textbox temp_students.txt 20 60
    rm -f temp_students.txt
}

show_faculty() {
    {
        echo "USERNAME    | GROUP"
        echo "--------------------"
        column -t -s ':' "$FACULTY_FILE"
    } > temp_faculty.txt
    dialog --textbox temp_faculty.txt 20 50
    rm -f temp_faculty.txt
}

view_admin_logs() {
    admin_user=$(authenticate_user "admin")
    if [ -z "$admin_user" ]; then return; fi

    while true; do
        choice=$(dialog --stdout --menu "Admin Panel" 18 60 5 \
            1 "View Sudo Commands Log" \
            2 "Clear Sudo Commands Log" \
            3 "Add Faculty" \
            4 "Remove Faculty" \
            5 "Back")
        case $choice in
            1) dialog --textbox "$SUDO_LOG" 20 80 ;;
            2) > "$SUDO_LOG"; dialog --msgbox "Sudo logs cleared." 6 40 ;;
            3) add_faculty ;;
            4) remove_faculty ;;
            5) break ;;
        esac
    done
}

faculty_menu() {
    faculty_user=$(authenticate_user "faculty")
    if [ -z "$faculty_user" ]; then return; fi

    while true; do
        choice=$(dialog --stdout --menu "Faculty Panel - Manage Students" 20 50 6 \
            1 "Add Student" \
            2 "Lock Student Account (by ID)" \
            3 "Unlock Student Account (by ID)" \
            4 "Set Account Expiry (by ID)" \
            5 "Remove Student" \
            6 "Back")
        case $choice in
            1) add_student ;;
            2) lock_student ;;
            3) unlock_student ;;
            4) set_expiry ;;
            5) remove_student ;;
            6) break ;;
        esac
    done
}

# Main Menu
while true; do
    option=$(dialog --stdout --menu "College Management System" 20 60 6 \
        1 "Student - View My Details" \
        2 "Faculty - Manage Students" \
        3 "Admin - View Logs & Manage Faculty" \
        4 "Show All Students" \
        5 "Show All Faculty" \
        6 "Exit")
    case $option in
        1) view_student_details ;;
        2) faculty_menu ;;
        3) view_admin_logs ;;
        4) show_students ;;
        5) show_faculty ;;
        6) clear; exit ;;
    esac
done
