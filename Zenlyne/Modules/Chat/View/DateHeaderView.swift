//
//  DateHeaderView.swift
//  Zenlyne
//
//  Created by admin on 3/6/25.
//

import SwiftUI

struct DateHeaderView: View {
    let date: Date
    
    var body: some View {
        HStack {
            Spacer()
            Text(formatDateHeader(date))
                .font(.caption)
                .fontWeight(.medium)
                .foregroundColor(.white)
                .padding(.horizontal, 12)
                .padding(.vertical, 6)
                .background(Color.black.opacity(0.7))
                .cornerRadius(12)
            Spacer()
        }
        .padding(.vertical, 8)
    }
    
    private func formatDateHeader(_ date: Date) -> String {
        let calendar = Calendar.current
        let now = Date()
        
        if calendar.isDateInToday(date) {
            return "Hôm nay"
        } else if calendar.isDateInYesterday(date) {
            return "Hôm qua"
        } else if calendar.isDate(date, equalTo: now, toGranularity: .weekOfYear) {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "vi_VN")
            formatter.dateFormat = "EEEE"
            return formatter.string(from: date).capitalized
        } else if calendar.isDate(date, equalTo: now, toGranularity: .year) {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "vi_VN")
            formatter.dateFormat = "dd 'tháng' MM"
            return formatter.string(from: date)
        } else {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: "vi_VN")
            formatter.dateFormat = "dd 'tháng' MM, yyyy"
            return formatter.string(from: date)
        }
    }
}
