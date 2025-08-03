package com.example.lambda.service;

import com.amazonaws.services.lambda.runtime.LambdaLogger;
import com.amazonaws.services.s3.AmazonS3;
import com.amazonaws.services.s3.AmazonS3ClientBuilder;
import com.amazonaws.services.s3.model.ObjectMetadata;
import com.opencsv.CSVWriter;

import java.io.*;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.List;
import java.util.Map;

/**
 * Service for S3 operations
 */
public class S3Service {
    private final AmazonS3 s3Client;
    
    public S3Service() {
        this.s3Client = AmazonS3ClientBuilder.defaultClient();
    }
    
    public S3Service(AmazonS3 s3Client) {
        this.s3Client = s3Client;
    }
    
    /**
     * Uploads data to S3 as CSV
     */
    public String uploadDataToCsv(List<Map<String, Object>> data, String bucket, 
                                String keyPrefix, LambdaLogger logger) {
        if (data == null || data.isEmpty()) {
            throw new IllegalArgumentException("Data cannot be null or empty");
        }
        
        // Generate timestamp-based key
        String timestamp = LocalDateTime.now().format(DateTimeFormatter.ofPattern("yyyyMMdd_HHmmss"));
        String key = keyPrefix + "/data_export_" + timestamp + ".csv";
        
        try {
            // Convert data to CSV
            byte[] csvData = convertToCsv(data);
            
            // Upload to S3
            ObjectMetadata metadata = new ObjectMetadata();
            metadata.setContentLength(csvData.length);
            metadata.setContentType("text/csv");
            
            try (ByteArrayInputStream inputStream = new ByteArrayInputStream(csvData)) {
                s3Client.putObject(bucket, key, inputStream, metadata);
            }
            
            String s3Url = String.format("s3://%s/%s", bucket, key);
            logger.log("Data uploaded successfully to: " + s3Url);
            
            return s3Url;
            
        } catch (Exception e) {
            logger.log("Failed to upload data to S3: " + e.getMessage());
            throw new RuntimeException("Failed to upload data to S3", e);
        }
    }
    
    /**
     * Converts data to CSV format
     */
    private byte[] convertToCsv(List<Map<String, Object>> data) throws IOException {
        try (ByteArrayOutputStream outputStream = new ByteArrayOutputStream();
             OutputStreamWriter writer = new OutputStreamWriter(outputStream);
             CSVWriter csvWriter = new CSVWriter(writer)) {
            
            if (!data.isEmpty()) {
                // Write header
                Map<String, Object> firstRow = data.get(0);
                String[] headers = firstRow.keySet().toArray(new String[0]);
                csvWriter.writeNext(headers);
                
                // Write data rows
                for (Map<String, Object> row : data) {
                    String[] values = new String[headers.length];
                    for (int i = 0; i < headers.length; i++) {
                        Object value = row.get(headers[i]);
                        values[i] = value != null ? value.toString() : "";
                    }
                    csvWriter.writeNext(values);
                }
            }
            
            writer.flush();
            return outputStream.toByteArray();
        }
    }
}
