#!/bin/bash

if [ ! -d tmp ]; then
    mkdir tmp
fi

for i in eater; do
    echo "Processing target: $i"
    
    # Compile with ca65
    ca65 -I ./inc -I "$HOME/cc65/asminc" --feature labels_without_colons --feature loose_string_term \
         -D $i msbasic.s -o tmp/$i.o --listing tmp/$i.lst -g
    if [ $? -ne 0 ]; then
        echo "Error compiling $i with ca65."
        continue
    fi
    
    # Link with ld65 - using correct options from your help output
    ld65 -o tmp/$i.bin tmp/$i.o -C $i.cfg \
         --mapfile tmp/$i.map \
         -vm \
         -Ln tmp/$i.lbl \
         --dbgfile tmp/$i.dbg
    if [ $? -ne 0 ]; then
        echo "Error linking $i with ld65."
        continue
    fi
    
    # Generate additional reports - FIXED FILENAME SYNTAX
    echo "=== ZERO PAGE ANALYSIS for $i ===" > "tmp/${i}_zp_report.txt"
    echo "" >> "tmp/${i}_zp_report.txt"
    
    # 1. Extract Zero Page symbols from label file (primary source) - FIXED PATTERN
    echo "1. ZERO PAGE SYMBOLS (from .lbl file):" >> "tmp/${i}_zp_report.txt"
    grep -E 'al 0000[0-9A-F][0-9A-F] ' "tmp/$i.lbl" | sort -k2 >> "tmp/${i}_zp_report.txt"
    echo "" >> "tmp/${i}_zp_report.txt"
    
    # 2. Extract Zero Page usage from map file
    echo "2. ZERO PAGE SEGMENT USAGE (from .map file):" >> "tmp/${i}_zp_report.txt"
    grep -A 10 -B 2 -i "zeropage\|ZP\|page.0" "tmp/$i.map" >> "tmp/${i}_zp_report.txt"
    echo "" >> "tmp/${i}_zp_report.txt"
    
    # 3. Show detailed segment information
    echo "3. SEGMENT DETAILS (from .map file):" >> "tmp/${i}_zp_report.txt"
    grep -A 3 -B 1 "ZEROPAGE\|ZP" "tmp/$i.map" >> "tmp/${i}_zp_report.txt"
    echo "" >> "tmp/${i}_zp_report.txt"
    
    # 4. Show Zero Page usage summary - ENHANCED WITH OVERLAP ANALYSIS
    echo "4. ZERO PAGE USAGE SUMMARY:" >> "tmp/${i}_zp_report.txt"
    zp_count=$(grep -E -c 'al 0000[0-9A-F][0-9A-F] ' "tmp/$i.lbl")
    echo "Total ZP symbols found: $zp_count" >> "tmp/${i}_zp_report.txt"
    
    # Calculate ZP memory usage
    if [ $zp_count -gt 0 ]; then
        # Extract unique addresses and find the highest one
        highest_zp=$(grep -E 'al 0000[0-9A-F][0-9A-F] ' "tmp/$i.lbl" | awk '{print $2}' | sort -u | tail -1)
        highest_zp_hex=$(echo $highest_zp | sed 's/0000//')
        zp_usage=$((0x$highest_zp_hex + 1))
        echo "Highest ZP address used: $highest_zp" >> "tmp/${i}_zp_report.txt"
        echo "ZP memory used: $zp_usage bytes" >> "tmp/${i}_zp_report.txt"
        echo "ZP memory free: $((256 - $zp_usage)) bytes" >> "tmp/${i}_zp_report.txt"
        
        # Calculate unique vs total counts
        unique_count=$(grep -E 'al 0000[0-9A-F][0-9A-F] ' "tmp/$i.lbl" | awk '{print $2}' | sort -u | wc -l)
        overlap_count=$((zp_count - unique_count))
        echo "Unique ZP addresses: $unique_count" >> "tmp/${i}_zp_report.txt"
        echo "Symbols with overlapping addresses: $overlap_count" >> "tmp/${i}_zp_report.txt"
        echo "" >> "tmp/${i}_zp_report.txt"
        
        # SHOW OVERLAPPING ADDRESSES DETAILS
        if [ $overlap_count -gt 0 ]; then
            echo "OVERLAPPING SYMBOLS (by address):" >> "tmp/${i}_zp_report.txt"
            # Find addresses with multiple symbols
            grep -E 'al 0000[0-9A-F][0-9A-F] ' "tmp/$i.lbl" | awk '{print $2 " " $3}' | \
            sort | uniq -c | grep -v '^ *1 ' | sort -nr >> "tmp/${i}_zp_report.txt"
            echo "" >> "tmp/${i}_zp_report.txt"
            
            echo "DETAILED OVERLAP ANALYSIS:" >> "tmp/${i}_zp_report.txt"
            # Group symbols by address and show all symbols at each overlapping address
            grep -E 'al 0000[0-9A-F][0-9A-F] ' "tmp/$i.lbl" | awk '{print $2 " " $3}' | \
            sort | awk '
            {
                if ($1 != prev_addr) {
                    if (count > 1) {
                        print prev_addr " has " count " symbols:";
                        for (i=0; i<count; i++) print "  " symbols[i];
                        print "";
                    }
                    count = 0;
                    prev_addr = $1;
                }
                symbols[count++] = $2;
            }
            END {
                if (count > 1) {
                    print prev_addr " has " count " symbols:";
                    for (i=0; i<count; i++) print "  " symbols[i];
                }
            }' >> "tmp/${i}_zp_report.txt"
        else
            echo "No overlapping symbols found." >> "tmp/${i}_zp_report.txt"
        fi
    else
        echo "ZP memory used: 0 bytes" >> "tmp/${i}_zp_report.txt"
        echo "ZP memory free: 256 bytes" >> "tmp/${i}_zp_report.txt"
    fi
    echo "" >> "tmp/${i}_zp_report.txt"
    
    # 5. Show assembly listing locations - FIXED TO FIND ACTUAL ZP MEMORY REFERENCES
    echo "5. ZERO PAGE MEMORY REFERENCES IN ASSEMBLY LISTING:" >> "tmp/${i}_zp_report.txt"
    
    # Look for ACTUAL zero page memory references (not immediate values)
    # Pattern: instructions that use zero page addressing (no # prefix)
    echo "ACTUAL ZERO PAGE MEMORY ACCESSES:" >> "tmp/${i}_zp_report.txt"
    
    # Look for instructions that use zero page addressing modes
    grep -n -E '\b(lda|sta|adc|sbc|cmp|and|ora|eor|bit|asl|lsr|rol|ror|dec|inc|st[xy]|ld[xy]|cp[xy])\b.*\$[0-9A-Fa-f]{2}[^0-9A-Fa-f]' "tmp/$i.lst" | \
    grep -v '#' | head -15 >> "tmp/${i}_zp_report.txt"
    
    # Look for zero page indexed addressing
    echo "" >> "tmp/${i}_zp_report.txt"
    echo "ZERO PAGE INDEXED ADDRESSING:" >> "tmp/${i}_zp_report.txt"
    grep -n -E '\$[0-9A-Fa-f]{2},[XY]' "tmp/$i.lst" | head -10 >> "tmp/${i}_zp_report.txt"
    
    # Look for indirect zero page addressing
    echo "" >> "tmp/${i}_zp_report.txt"
    echo "INDIRECT ZERO PAGE ADDRESSING:" >> "tmp/${i}_zp_report.txt"
    grep -n -E '\([^)]*\$[0-9A-Fa-f]{2}' "tmp/$i.lst" | head -10 >> "tmp/${i}_zp_report.txt"
    
    echo "(showing first occurrences of each addressing mode)" >> "tmp/${i}_zp_report.txt"
    echo "" >> "tmp/${i}_zp_report.txt"
    
    echo "" >> "tmp/${i}_zp_report.txt"
    
    # 6. Show which specific variables are in zero page
    echo "6. SPECIFIC ZERO PAGE VARIABLES:" >> "tmp/${i}_zp_report.txt"
    grep -E 'al 0000[0-9A-F][0-9A-F] ' "tmp/$i.lbl" | awk '{printf "%-20s %s\n", $3, $2}' >> "tmp/${i}_zp_report.txt"
    echo "" >> "tmp/${i}_zp_report.txt"
    
    echo "Successfully processed $i"
    echo "Zero page report generated: tmp/${i}_zp_report.txt"
done

# Generate final summary
echo ""
echo "=== PROCESSING COMPLETE ==="
echo "Generated files in tmp/ directory:"
ls -la tmp/*.map tmp/*.lbl tmp/*_report.txt 2>/dev/null || echo "Some files may not have been generated due to errors"
