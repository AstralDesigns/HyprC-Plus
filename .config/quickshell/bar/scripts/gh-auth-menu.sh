#!/usr/bin/env bash
# GitHub CLI Interactive Account Manager for HyprCandy Control Center

while true; do
    clear
    echo -e "\033[1;36m====================================================\033[0m"
    echo -e "\033[1;36m           GitHub CLI Account Manager               \033[0m"
    echo -e "\033[1;36m====================================================\033[0m"
    echo ""
    gh auth status 2>&1
    echo ""
    echo -e "\033[1;33mActions:\033[0m"
    echo "  1) Switch active account  (gh auth switch)"
    echo "  2) Log in / Add account   (gh auth login)"
    echo "  3) Log out of an account  (gh auth logout)"
    echo "  4) Refresh status"
    echo "  5) Exit"
    echo ""
    read -rp "Select an option [1-5]: " choice
    case "$choice" in
        1)
            echo ""
            gh auth switch
            echo ""
            read -rp "Press Enter to return to menu..."
            ;;
        2)
            echo ""
            gh auth login
            echo ""
            read -rp "Press Enter to return to menu..."
            ;;
        3)
            echo ""
            gh auth logout
            echo ""
            read -rp "Press Enter to return to menu..."
            ;;
        4)
            continue
            ;;
        5|q|Q|"")
            break
            ;;
        *)
            echo "Invalid option."
            sleep 1
            ;;
    esac
done
