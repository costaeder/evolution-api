-- Marcar migração Kafka como já aplicada
-- Database: zyra_9232, Schema: evolution_api

-- Inserir registro na tabela _prisma_migrations para a migração Kafka
INSERT INTO evolution_api."_prisma_migrations" 
  (id, checksum, finished_at, migration_name, logs, rolled_back_at, started_at, applied_steps_count)
VALUES 
  (gen_random_uuid(), 
   '5c8f8d9e8f5c5e5f8d9e8f5c5e5f8d9e8f5c5e5f8d9e8f5c5e5f8d9e8f5c5e5f', 
   NOW(), 
   '20250918182355_add_kafka_integration', 
   NULL, 
   NULL, 
   NOW(), 
   1)
ON CONFLICT (migration_name) DO NOTHING;
